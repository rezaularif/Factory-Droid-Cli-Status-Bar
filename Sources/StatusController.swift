import Cocoa

final class StatusController: NSObject, NSMenuDelegate {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let store = SessionStore()

    private var pollTimer: Timer?
    private var animTimer: Timer?
    private var frameIdx = 0
    private let launchedAt = Date()
    private var notNeededSince: Date?

    private var menuIsOpen = false
    private var sessionMenuItems: [(item: NSMenuItem, id: String)] = []
    private var activeBase = ""
    private var startedAt: Double = 0
    private var activeColor: NSColor?
    private var activityIndex = 0
    private var activitySessionID = ""
    private var activityCycleAt = Date.distantPast
    private let activityCycleInterval: TimeInterval = 1.8

    /// Animation styles from Droid CLI + three-dot default.
    enum AnimStyle: String {
        case threeDots  // ● ○ ○ horizontal three-dot loader (default)
        case dots       // Droid TUI braille (⠋…⠏)
        case dots10     // Droid streaming braille
        case dots2      // Droid block braille
        case breathe    // Droid breathe
        case orbit      // Droid orbit
        case logo       // Droid FullScreenAnimation logo frames
        // Migrated legacy keys (old Claude-port styles) → threeDots
        case spark, crab, web, code

        var resolved: AnimStyle {
            switch self {
            case .spark, .crab, .web, .code: return .threeDots
            default: return self
            }
        }

        var menuTitle: String {
            switch resolved {
            case .threeDots: return "Three dots"
            case .dots: return "Braille (CLI)"
            case .dots10: return "Dots 10 (stream)"
            case .dots2: return "Block"
            case .breathe: return "Breathe"
            case .orbit: return "Orbit"
            case .logo: return "Droid Logo"
            default: return rawValue
            }
        }
    }
    var animStyle: AnimStyle = .threeDots
    var showTimer = false
    var iconSystem = false
    /// Off by default: show real Droid activity (tool/file/prompt), not random verbs.
    var useThinkingWords = false

    // Cached glyph masks for Droid braille presets
    private lazy var droidGlyphMasks: [String: [NSImage]] = {
        var map: [String: [NSImage]] = [:]
        for p in DroidSpinners.all {
            map[p.name] = p.frames.map { StatusController.glyphMask($0) }
        }
        return map
    }()

    // Cached raster frames for the Droid logo animation (subsampled).
    private lazy var droidLogoImages: [NSImage] = {
        let indices = DroidLogoFrames.sampleIndices
        return indices.compactMap { i -> NSImage? in
            guard i < DroidLogoFrames.frames.count else { return nil }
            return DroidLogoFrames.image(for: DroidLogoFrames.frames[i], color: Brand.accent)
        }
    }()
    private lazy var droidLogoTemplateImages: [NSImage] = {
        let indices = DroidLogoFrames.sampleIndices
        return indices.compactMap { i -> NSImage? in
            guard i < DroidLogoFrames.frames.count else { return nil }
            return DroidLogoFrames.image(for: DroidLogoFrames.frames[i], color: nil)
        }
    }()
    private lazy var droidRestingLogo: NSImage? = {
        guard DroidLogoFrames.restingIndex < DroidLogoFrames.frames.count else { return nil }
        return DroidLogoFrames.image(
            for: DroidLogoFrames.frames[DroidLogoFrames.restingIndex],
            color: iconSystem ? nil : Brand.accent)
    }()

    private var iconColor: NSColor? { iconSystem ? nil : Brand.accent }

    private var activeStyle: AnimStyle { animStyle.resolved }

    private var activePreset: DroidSpinners.Preset? {
        switch activeStyle {
        case .dots: return DroidSpinners.dots
        case .dots10: return DroidSpinners.dots10
        case .dots2: return DroidSpinners.dots2
        case .breathe: return DroidSpinners.breathe
        case .orbit: return DroidSpinners.orbit
        default: return nil
        }
    }

    private var fps: Double {
        if activeStyle == .threeDots { return DroidSpinners.threeDotsFPS }
        if let p = activePreset { return p.fps }
        if activeStyle == .logo { return 12 }
        return 12
    }
    private var frameCount: Int {
        if activeStyle == .threeDots { return 3 }
        if let p = activePreset { return max(1, p.frames.count) }
        if activeStyle == .logo { return max(1, droidLogoImages.count) }
        return 1
    }

    override init() {
        super.init()
        let d = UserDefaults.standard
        if d.object(forKey: "showTimer") != nil { showTimer = d.bool(forKey: "showTimer") }
        if d.object(forKey: "iconSystem") != nil { iconSystem = d.bool(forKey: "iconSystem") }
        if d.object(forKey: "thinkingWords") != nil { useThinkingWords = d.bool(forKey: "thinkingWords") }
        if let s = d.string(forKey: "animStyle"), let st = AnimStyle(rawValue: s) {
            animStyle = st.resolved
        }

        // Ensure the status item is visible and has a clickable button.
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.toolTip = "Droid Status Bar"
        }

        let menu = NSMenu()
        menu.autoenablesItems = true
        menu.delegate = self
        statusItem.menu = menu
        render(label: "", color: iconColor, animate: false, startedAt: 0)

        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        pollTimer = t
        tick()
        ensureHooksInstalled()
    }

    // MARK: - Hooks install

    func ensureHooksInstalled() {
        let d = UserDefaults.standard
        let current = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
        // Always reinstall when version changes; also retry if never succeeded.
        guard d.string(forKey: "installedVersion") != current,
              let installer = Bundle.main.path(forResource: "install", ofType: "js") else { return }
        DispatchQueue.global().async {
            guard let node = Self.locateNode() else {
                NSLog("DroidStatusBar: node not found; hooks not installed")
                return
            }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: node)
            task.arguments = [installer]
            try? task.run()
            task.waitUntilExit()
            if task.terminationStatus == 0 {
                UserDefaults.standard.set(current, forKey: "installedVersion")
            }
        }
    }

    static func locateNode() -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
            "\(home)/.volta/bin/node",
            "\(home)/.asdf/shims/node",
        ]
        let nvmDir = "\(home)/.nvm/versions/node"
        if let versions = try? fm.contentsOfDirectory(atPath: nvmDir) {
            for v in versions.sorted(by: >) { candidates.append("\(nvmDir)/\(v)/bin/node") }
        }
        for path in candidates where fm.isExecutableFile(atPath: path) { return path }

        for args in [["-ilc", "command -v node"], ["-lc", "command -v node"]] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = args
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { continue }
            p.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = (String(data: data, encoding: .utf8) ?? "")
                .split(separator: "\n").last.map(String.init)?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !path.isEmpty, fm.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    // MARK: - Tick

    func tick() {
        store.reload()
        let lead = store.evaluate()
        updateActivityCycle(lead)
        applyLead(lead)
        if menuIsOpen { refreshOpenMenuRows() }
        // Decide lifecycle from the same freshly loaded snapshot that was just
        // rendered. This avoids a poll-window where a new prompt can be missed.
        checkLifecycle()
    }

    private func applyLead(_ lead: Session?) {
        statusItem.button?.toolTip = lead.map(tooltip(for:))
        guard let lead = lead else { renderResting(); return }
        switch lead.eff {
        case SessionState.permission:
            render(label: permissionText(lead), color: Brand.amber, animate: false, startedAt: 0, dot: true)
        case SessionState.thinking, SessionState.tool:
            render(label: statusText(lead), color: iconColor, animate: true, startedAt: lead.startedAt)
        default:
            renderResting()
        }
    }

    private func updateActivityCycle(_ lead: Session?) {
        guard let lead,
              lead.eff == SessionState.thinking || lead.eff == SessionState.tool else {
            activityIndex = 0
            activitySessionID = ""
            activityCycleAt = Date.distantPast
            return
        }
        let labels = store.activityLabels(lead, useThinkingWords: useThinkingWords)
        guard labels.count > 1 else {
            activityIndex = 0
            activitySessionID = lead.id
            activityCycleAt = Date()
            return
        }
        if activitySessionID != lead.id {
            activitySessionID = lead.id
            activityIndex = 0
            activityCycleAt = Date()
            return
        }
        let now = Date()
        if now.timeIntervalSince(activityCycleAt) >= activityCycleInterval {
            activityIndex = (activityIndex + 1) % labels.count
            activityCycleAt = now
        }
        if activityIndex >= labels.count { activityIndex = 0 }
    }

    private func displayedActivity(_ s: Session) -> String {
        let labels = store.activityLabels(s, useThinkingWords: useThinkingWords)
        guard !labels.isEmpty else { return "" }
        guard s.id == activitySessionID, labels.count > 1 else { return labels[0] }
        return labels[activityIndex % labels.count]
    }

    private func tooltip(for s: Session) -> String {
        var line = store.sessionName(s)
        if !s.branch.isEmpty { line += " · " + s.branch }
        if !s.cwd.isEmpty { line += "\n" + s.cwd }
        let label = statusText(s)
        if !label.isEmpty { line += "\n" + label }
        line += "\nStatus: " + stateLabel(s.eff)
        if s.ts > 0 {
            line += "\nUpdated " + elapsed(max(0, Int(Date().timeIntervalSince1970 - s.ts))) + " ago"
        }
        return line
    }

    private func statusText(_ s: Session) -> String {
        switch s.eff {
        case SessionState.permission, SessionState.thinking, SessionState.tool:
            return store.statusBarText(
                s, useThinkingWords: useThinkingWords, activityOverride: displayedActivity(s))
        case SessionState.done:
            let name = store.sessionName(s)
            return name.isEmpty ? "Done" : name
        default:
            return store.sessionName(s)
        }
    }

    private func permissionText(_ s: Session) -> String {
        let detail = displayedActivity(s)
        return detail.isEmpty ? "Approve" : "Approve · " + detail
    }

    // MARK: - Lifecycle

    func factoryDesktopRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == Brand.factoryBundleID
        }
    }

    /// Icon stays only while a session is actively working (thinking / tool / permission).
    /// Idle/done sessions, empty state, or Factory Desktop alone do NOT keep us alive.
    /// Hooks relaunch the app on the next prompt/tool.
    func needsToStayAlive() -> Bool {
        let now = Date().timeIntervalSince1970
        for s in store.sessions.values {
            let eff = s.eff.isEmpty ? store.effectiveState(s, now: now) : s.eff
            if eff == SessionState.thinking
                || eff == SessionState.tool
                || eff == SessionState.permission {
                return true
            }
        }
        return false
    }

    func checkLifecycle() {
        let now = Date()
        // Short settle only when we actually have work; otherwise quit quickly after a
        // manual launch / leftover open with nothing active.
        let grace: TimeInterval = needsToStayAlive() ? Timeouts.launchGrace : 0.8
        if now.timeIntervalSince(launchedAt) < grace { return }
        if needsToStayAlive() {
            notNeededSince = nil
            // Ensure the item is visible while working.
            statusItem.isVisible = true
            return
        }
        // Nothing active — hide immediately, then quit after a brief debounce.
        statusItem.isVisible = false
        if let since = notNeededSince {
            if now.timeIntervalSince(since) >= Timeouts.idleQuit { NSApp.terminate(nil) }
        } else {
            notNeededSince = now
        }
    }

    // MARK: - Menu

    func menuWillOpen(_ menu: NSMenu) { menuIsOpen = true }
    func menuDidClose(_ menu: NSMenu) {
        menuIsOpen = false
        sessionMenuItems.removeAll()
    }

    func refreshOpenMenuRows() {
        let now = Date().timeIntervalSince1970
        for (item, id) in sessionMenuItems {
            guard let s = store.sessions[id], let v = item.view as? SessionRowView else { continue }
            let eff = s.eff.isEmpty ? store.effectiveState(s, now: now) : s.eff
            configureSessionRow(v, s, eff: eff)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        store.refreshBranches()
        sessionMenuItems.removeAll()
        let now = Date().timeIntervalSince1970
        let visible = store.visibleSessions(now: now)

        if !visible.isEmpty {
            menu.addItem(header("Sessions"))
            for s in visible {
                let eff = s.eff.isEmpty ? store.effectiveState(s, now: now) : s.eff
                let view = SessionRowView(id: s.id, width: CGFloat(uiConfig()["boxWidth"] ?? 300))
                let sid = s.id, ep = s.entrypoint, tp = s.termProgram
                view.onClick = { [weak self] in
                    menu.cancelTracking()
                    self?.openSession(sid, entrypoint: ep, termProgram: tp)
                }
                configureSessionRow(view, s, eff: eff)
                let it = NSMenuItem()
                it.view = view
                menu.addItem(it)
                sessionMenuItems.append((it, s.id))
            }
            menu.addItem(.separator())
        } else if factoryDesktopRunning() {
            menu.addItem(header("Sessions"))
            let open = NSMenuItem(title: "Open Factory", action: #selector(openFactory), keyEquivalent: "")
            open.target = self
            menu.addItem(open)
            menu.addItem(.separator())
        }

        menu.addItem(header("Options"))
        menu.addItem(toggleRow(title: "Show timer", isOn: showTimer) { [weak self] on in
            self?.showTimer = on
            UserDefaults.standard.set(on, forKey: "showTimer")
            self?.applyTitle()
        })
        menu.addItem(toggleRow(title: "Playful words", isOn: useThinkingWords) { [weak self] on in
            self?.useThinkingWords = on
            UserDefaults.standard.set(on, forKey: "thinkingWords")
            self?.tick()
        })

        let animParent = NSMenuItem(title: "Animation", action: nil, keyEquivalent: "")
        let animSub = NSMenu()
        let styles: [AnimStyle] = [.threeDots, .dots, .dots10, .dots2, .breathe, .orbit, .logo]
        for style in styles {
            let it = NSMenuItem(title: style.menuTitle, action: #selector(chooseStyle(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = style.rawValue
            it.state = activeStyle == style ? .on : .off
            animSub.addItem(it)
        }
        animParent.submenu = animSub
        menu.addItem(animParent)

        let colorParent = NSMenuItem(title: "Color", action: nil, keyEquivalent: "")
        let colorSub = NSMenu()
        for (sys, name) in [(false, "Accent"), (true, "System")] {
            let it = NSMenuItem(title: name, action: #selector(chooseColor(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = sys
            it.state = iconSystem == sys ? .on : .off
            colorSub.addItem(it)
        }
        colorParent.submenu = colorSub
        menu.addItem(colorParent)

        menu.addItem(.separator())
        let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        menu.addItem(NSMenuItem(title: "Version \(ver)", action: nil, keyEquivalent: ""))
        let q = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        q.target = self
        menu.addItem(q)
    }

    private func header(_ title: String) -> NSMenuItem {
        if #available(macOS 14.0, *) { return NSMenuItem.sectionHeader(title: title) }
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.isEnabled = false
        return it
    }

    private func toggleRow(title: String, isOn: Bool, onToggle: @escaping (Bool) -> Void) -> NSMenuItem {
        let width = CGFloat(uiConfig()["boxWidth"] ?? 300), height: CGFloat = 24
        let leftInset: CGFloat = 14, rightInset: CGFloat = 12
        let row = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        row.autoresizingMask = [.width]

        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.sizeToFit()
        label.setFrameOrigin(NSPoint(x: leftInset, y: (height - label.frame.height) / 2))
        label.autoresizingMask = [.maxXMargin]
        row.addSubview(label)

        let toggle = ToggleView(isOn: isOn)
        toggle.onToggle = onToggle
        toggle.setFrameOrigin(NSPoint(
            x: width - toggle.frame.width - rightInset,
            y: (height - toggle.frame.height) / 2))
        toggle.autoresizingMask = [.minXMargin]
        row.addSubview(toggle)

        let item = NSMenuItem()
        item.view = row
        return item
    }

    private func uiConfig() -> [String: Double] {
        guard let d = FileManager.default.contents(atPath: Paths.uiConfig),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        return j.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }

    private func configureSessionRow(_ v: SessionRowView, _ s: Session, eff: String) {
        let cfg = uiConfig()
        let now = Date().timeIntervalSince1970
        let nameMax = Int(cfg["nameMax"] ?? 30)
        let working = (eff == SessionState.thinking || eff == SessionState.tool) && s.startedAt > 0
        let resting = !(eff == SessionState.permission
            || eff == SessionState.thinking
            || eff == SessionState.tool)
        let tag = surfaceTag(s.entrypoint)
        v.configure(
            icon: sessionSymbol(eff: eff),
            iconTint: resting ? .tertiaryLabelColor : .labelColor,
            spinning: (eff == SessionState.thinking || eff == SessionState.tool),
            name: truncated(store.sessionName(s), max: nameMax, keep: nameMax),
            activity: sessionActivity(s, eff: eff),
            branch: truncated(s.branch, max: 22, keep: 20),
            timer: working ? elapsed(max(0, Int(now - s.startedAt))) : nil,
            pillNormal: tag.isEmpty ? nil : pillImage(tag),
            pillSelected: tag.isEmpty ? nil : pillImage(tag, selected: true),
            pillInset: CGFloat(cfg["pillInset"] ?? 12),
            timerGap: CGFloat(cfg["timerGap"] ?? 10))
        var tip = store.sessionName(s)
        if !s.branch.isEmpty { tip += " · " + s.branch }
        let activity = store.activityLabel(s, useThinkingWords: useThinkingWords)
        if !activity.isEmpty { tip += "\n" + activity }
        tip += "\nStatus: " + stateLabel(eff)
        if s.ts > 0 {
            tip += "\nUpdated " + elapsed(max(0, Int(now - s.ts))) + " ago"
        }
        if !s.tool.isEmpty { tip += "\nTool: " + s.tool }
        if !s.cwd.isEmpty { tip += "\n" + s.cwd }
        v.toolTip = tip
    }

    private func stateLabel(_ eff: String) -> String {
        switch eff {
        case SessionState.permission: return "Needs permission"
        case SessionState.thinking: return "Streaming"
        case SessionState.tool: return "Using a tool"
        case SessionState.done: return "Done"
        default: return "Idle"
        }
    }

    private func sessionActivity(_ s: Session, eff: String) -> String {
        let detail = displayedActivity(s)
        let state = stateLabel(eff)
        return detail.isEmpty ? state : state + " · " + detail
    }

    private func surfaceTag(_ entrypoint: String) -> String {
        switch entrypoint {
        case "factory-desktop": return "APP"
        case "": return ""
        default: return "CLI"
        }
    }

    private func pillImage(_ text: String, selected: Bool = false) -> NSImage {
        let t = text as NSString
        let font = NSFont.monospacedSystemFont(ofSize: 9.5, weight: .semibold)
        let pad: CGFloat = 7, h: CGFloat = 15
        let cfg = uiConfig()
        let dy = CGFloat(cfg["pillTextY"] ?? -1)
        let dark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let bgAlpha = CGFloat(cfg[dark ? "pillBgDark" : "pillBgLight"] ?? (dark ? 0.14 : 0.10))
        let bg = selected ? NSColor.white.withAlphaComponent(0.22)
                          : (dark ? NSColor.white : NSColor.black).withAlphaComponent(bgAlpha)
        let fg = selected ? NSColor.white : NSColor.labelColor
        let w = ceil(t.size(withAttributes: [.font: font]).width) + pad * 2
        return NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            bg.setFill()
            NSBezierPath(roundedRect: rect, xRadius: h / 2, yRadius: h / 2).fill()
            let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: fg]
            let ts = t.size(withAttributes: a)
            t.draw(at: NSPoint(x: (rect.width - ts.width) / 2, y: (rect.height - ts.height) / 2 + dy),
                   withAttributes: a)
            return true
        }
    }

    private func sessionSymbol(eff: String) -> NSImage? {
        switch eff {
        case SessionState.permission:
            return symbolImage("exclamationmark.circle.fill", tint: Brand.amber)
        case SessionState.thinking, SessionState.tool:
            return nil
        default:
            return restingCaret
        }
    }

    private lazy var restingCaret: NSImage? = {
        let glyph = "\u{276F}" as NSString
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let side: CGFloat = 15
        let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            let g = glyph.size(withAttributes: attrs)
            glyph.draw(at: NSPoint(x: (side - g.width) / 2, y: (side - g.height) / 2), withAttributes: attrs)
            return true
        }
        img.isTemplate = true
        return img
    }()

    private func symbolImage(_ name: String, tint: NSColor? = nil) -> NSImage? {
        guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        if let tint = tint, #available(macOS 12.0, *) {
            return img.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [tint]))
        }
        img.isTemplate = true
        return img
    }

    private func truncated(_ s: String, max: Int = 20, keep: Int = 18) -> String {
        s.count > max ? String(s.prefix(keep)) + "…" : s
    }

    private func elapsed(_ secs: Int) -> String {
        let m = secs / 60, s = secs % 60
        return m > 0 ? "\(m)m \(s)s" : "\(s)s"
    }

    // MARK: - Actions

    @objc func quit() { NSApp.terminate(nil) }

    @objc func openFactory() {
        let ws = NSWorkspace.shared
        if let url = ws.urlForApplication(withBundleIdentifier: Brand.factoryBundleID) {
            ws.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    func openSession(_ id: String, entrypoint: String, termProgram: String) {
        if entrypoint == "factory-desktop" { openFactory(); return }
        let app: String
        switch termProgram {
        case "Apple_Terminal": app = "Terminal"
        case "iTerm.app": app = "iTerm"
        case "vscode": app = "Visual Studio Code"
        case "WarpTerminal": app = "Warp"
        case "ghostty": app = "Ghostty"
        case "": return
        default: app = termProgram
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        p.arguments = ["-a", app]
        try? p.run()
    }

    @objc func chooseColor(_ sender: NSMenuItem) {
        guard let sys = sender.representedObject as? Bool else { return }
        iconSystem = sys
        UserDefaults.standard.set(iconSystem, forKey: "iconSystem")
        tick()
    }

    @objc func chooseStyle(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let st = AnimStyle(rawValue: raw) else { return }
        animStyle = st.resolved
        UserDefaults.standard.set(animStyle.rawValue, forKey: "animStyle")
        animTimer?.invalidate(); animTimer = nil
        frameIdx = 0
        tick()
    }

    // MARK: - Render

    private func renderResting() { render(label: "", color: iconColor, animate: false, startedAt: 0) }

    private func render(label: String, color: NSColor?, animate: Bool, startedAt: Double, dot: Bool = false) {
        guard let button = statusItem.button else { return }
        button.contentTintColor = nil
        activeBase = label
        activeColor = color
        self.startedAt = startedAt

        if animate {
            if animTimer == nil {
                let t = Timer(timeInterval: 1.0 / fps, repeats: true) { [weak self] _ in self?.animStep() }
                RunLoop.main.add(t, forMode: .common)
                animTimer = t
            }
        } else {
            animTimer?.invalidate(); animTimer = nil
            frameIdx = 0
            button.image = dot ? dotIcon(color: color) : restingIcon(color: color)
        }
        applyTitle()
        if button.image == nil {
            button.image = dot ? dotIcon(color: color) : restingIcon(color: color)
        }
    }

    private func animStep() {
        frameIdx = (frameIdx + 1) % frameCount
        statusItem.button?.image = iconImage(color: activeColor, frame: frameIdx)
        applyTitle()
    }

    private func applyTitle() {
        guard let button = statusItem.button else { return }
        // Absolute ceiling including timer so we never shove other menu-bar icons.
        let hardMax = SessionStore.menuBarMaxChars + 8  // e.g. 18 + "  12m 3s"
        var text = activeBase
        if showTimer, startedAt > 0 {
            let clock = elapsed(max(0, Int(Date().timeIntervalSince1970 - startedAt)))
            let budget = max(6, hardMax - clock.count - 2)
            if text.count > budget {
                text = String(text.prefix(budget - 1)) + "…"
            }
            text += "  " + clock
        } else if text.count > SessionStore.menuBarMaxChars {
            text = String(text.prefix(SessionStore.menuBarMaxChars - 1)) + "…"
        }
        if text.isEmpty {
            button.imagePosition = .imageOnly
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        button.imagePosition = .imageLeading
        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular),
        ]
        button.attributedTitle = NSAttributedString(string: " \(text)", attributes: attrs)
    }

    // MARK: - Icons

    private func iconImage(color: NSColor?, frame: Int) -> NSImage {
        switch activeStyle {
        case .threeDots:
            return DroidSpinners.threeDotFrame(active: frame % 3, color: color)
        case .logo:
            let pool = color == nil ? droidLogoTemplateImages : droidLogoImages
            guard !pool.isEmpty else {
                return DroidSpinners.threeDotFrame(active: frame % 3, color: color)
            }
            return pool[frame % pool.count]
        default:
            let preset = activePreset ?? DroidSpinners.dots
            return droidGlyphIcon(preset: preset, color: color, frame: frame)
        }
    }

    /// Render one braille/glyph frame from a Droid CLI spinner preset.
    private func droidGlyphIcon(preset: DroidSpinners.Preset, color: NSColor?, frame: Int) -> NSImage {
        let s: CGFloat = 18
        let masks = droidGlyphMasks[preset.name] ?? preset.frames.map { StatusController.glyphMask($0) }
        guard !masks.isEmpty else { return NSImage(size: NSSize(width: s, height: s)) }
        let mask = masks[frame % masks.count]
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            let r = NSRect(x: 1, y: 1, width: s - 2, height: s - 2)
            if let c = color {
                c.setFill(); r.fill()
                mask.draw(in: r, from: .zero, operation: .destinationIn, fraction: 1.0)
            } else {
                mask.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1.0)
            }
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }

    static func glyphMask(_ g: String) -> NSImage {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 180), .foregroundColor: NSColor.black,
        ]
        let str = NSAttributedString(string: g, attributes: attrs)
        let sz = str.size()
        let big = NSImage(size: sz, flipped: false) { _ in str.draw(at: .zero); return true }
        guard let rep = big.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)) else {
            return NSImage(size: NSSize(width: 60, height: 60))
        }
        let w = rep.pixelsWide, h = rep.pixelsHigh, data = rep.bitmapData!
        var minx = w, miny = h, maxx = -1, maxy = -1
        for y in 0..<h {
            for x in 0..<w where data[(y * w + x) * 4 + 3] > 20 {
                minx = min(minx, x); maxx = max(maxx, x); miny = min(miny, y); maxy = max(maxy, y)
            }
        }
        guard maxx >= 0 else { return NSImage(size: NSSize(width: 60, height: 60)) }
        let bw = CGFloat(maxx - minx + 1), bh = CGFloat(maxy - miny + 1)
        let out: CGFloat = 60, fill = out * 0.92
        let scale = fill / max(bw, bh)
        let dw = bw * scale, dh = bh * scale
        let srcRect = NSRect(x: CGFloat(minx), y: CGFloat(h - maxy - 1), width: bw, height: bh)
        return NSImage(size: NSSize(width: out, height: out), flipped: false) { _ in
            big.draw(in: NSRect(x: (out - dw) / 2, y: (out - dh) / 2, width: dw, height: dh),
                     from: srcRect, operation: .sourceOver, fraction: 1.0)
            return true
        }
    }

    private func restingIcon(color: NSColor?) -> NSImage {
        switch activeStyle {
        case .threeDots:
            return DroidSpinners.threeDotResting(color: color)
        case .logo:
            if let logo = droidRestingLogo {
                if color == nil {
                    return DroidLogoFrames.image(
                        for: DroidLogoFrames.frames[DroidLogoFrames.restingIndex], color: nil)
                }
                return logo
            }
            return DroidSpinners.threeDotResting(color: color)
        default:
            let preset = activePreset ?? DroidSpinners.dots
            return droidGlyphIcon(preset: preset, color: color, frame: 0)
        }
    }

    private func dotIcon(color: NSColor?) -> NSImage {
        let s: CGFloat = 18, d: CGFloat = 9
        let img = NSImage(size: NSSize(width: s, height: s), flipped: false) { _ in
            (color ?? .systemYellow).setFill()
            NSBezierPath(ovalIn: NSRect(x: (s - d) / 2, y: (s - d) / 2, width: d, height: d)).fill()
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }
}
