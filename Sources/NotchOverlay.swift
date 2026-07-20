import Cocoa

/// A non-activating activity surface attached to the built-in camera housing.
/// At rest its visible frame follows the hardware notch with a small animated
/// Droid indicator attached to its right edge. Hovering grows it just enough to
/// reveal the current task below the obscured camera area.
final class NotchOverlayController {
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?
    var onAvailabilityChange: ((Bool) -> Void)?

    private let panel: NSPanel
    private let content = NotchOverlayView()
    private var targetScreen: NSScreen?
    private var screenObserver: NSObjectProtocol?
    private var hoverTimer: Timer?
    private var collapseWorkItem: DispatchWorkItem?
    private var revealUntil: Date?
    private var currentSessionID = ""
    private var currentAttention = false
    private var isExpanded = false
    private var suppressHoverUntilExit = false
    private var transitionID = 0

    var isAvailable: Bool { targetScreen != nil }

    init() {
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle,
        ]
        panel.contentView = content
        content.onHoverChange = { [weak self] hovered in self?.handleHover(hovered) }
        content.onClick = { [weak self] in
            self?.dismissForClick()
            self?.onClick?()
        }
        content.onRightClick = { [weak self] in
            self?.dismissForClick()
            self?.onRightClick?()
        }

        refreshScreen()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main) { [weak self] _ in
                self?.refreshScreen(notify: true)
            }
    }

    deinit {
        collapseWorkItem?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    /// Updates the live activity. Passing an empty title retracts the surface.
    func show(
        sessionID: String,
        title: String,
        detail: String,
        elapsed: String?,
        indicator: NSImage?,
        toolTip: String?,
        color: NSColor,
        pulses: Bool,
        attention: Bool
    ) {
        guard let screen = targetScreen, !title.isEmpty else {
            hide()
            return
        }

        let sessionChanged = !sessionID.isEmpty && sessionID != currentSessionID
        let attentionStarted = attention && !currentAttention
        let attentionEnded = !attention && currentAttention
        currentSessionID = sessionID
        currentAttention = attention
        if attentionEnded { revealUntil = nil }
        transitionID += 1
        content.configure(
            title: title,
            detail: detail,
            elapsed: elapsed,
            indicator: indicator,
            toolTip: toolTip,
            color: color,
            pulses: pulses,
            attention: attention)
        let frame = panelFrame(on: screen, expanded: isExpanded)
        startHoverPolling()

        if !panel.isVisible {
            isExpanded = false
            content.setExpanded(false, animated: false)
            panel.hasShadow = false
            panel.setFrame(panelFrame(on: screen, expanded: false), display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        } else if !panel.frame.equalTo(frame) {
            // Screen changes should keep the housing centered even before the
            // next hover transition.
            panel.setFrame(frame, display: true)
        }

        if attentionStarted {
            reveal(for: 3.2)
        } else if sessionChanged {
            reveal(for: 1.35)
        }
    }

    func hide(animated: Bool = true) {
        guard panel.isVisible else { return }
        transitionID += 1
        let thisTransition = transitionID
        isExpanded = false
        suppressHoverUntilExit = false
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        revealUntil = nil
        currentSessionID = ""
        currentAttention = false
        hoverTimer?.invalidate()
        hoverTimer = nil
        content.setExpanded(false, animated: false)
        if !animated {
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.transitionID == thisTransition else { return }
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
        })
    }

    func popUp(_ menu: NSMenu) {
        guard panel.isVisible else { return }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: content.bounds.midX, y: content.bounds.minY),
            in: content)
    }

    private func setExpanded(_ expanded: Bool) {
        if expanded {
            collapseWorkItem?.cancel()
            collapseWorkItem = nil
        }
        guard expanded != isExpanded, let screen = targetScreen, panel.isVisible else { return }
        isExpanded = expanded
        transitionID += 1
        content.setExpanded(expanded, animated: true)
        panel.hasShadow = expanded

        let frame = panelFrame(on: screen, expanded: expanded)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = expanded ? 0.24 : 0.18
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: expanded ? 0.16 : 0.4,
                expanded ? 0.88 : 0.0,
                expanded ? 0.24 : 0.6,
                1.0)
            panel.animator().setFrame(frame, display: true)
        }
    }

    private func handleHover(_ hovered: Bool) {
        if hovered, suppressHoverUntilExit { return }
        if hovered {
            setExpanded(true)
        } else if revealUntil.map({ $0 > Date() }) != true {
            scheduleCollapse()
        }
    }

    private func dismissForClick() {
        suppressHoverUntilExit = true
        revealUntil = nil
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        setExpanded(false)
    }

    private func reveal(for duration: TimeInterval) {
        revealUntil = Date().addingTimeInterval(duration)
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
        setExpanded(true)
    }

    private func scheduleCollapse() {
        guard collapseWorkItem == nil, isExpanded else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.collapseWorkItem = nil
            if self.revealUntil.map({ $0 > Date() }) == true { return }
            self.setExpanded(false)
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: item)
    }

    private func startHoverPolling() {
        guard hoverTimer == nil else { return }
        let timer = Timer(timeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.pollHover()
        }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    /// macOS can withhold normal tracking events over pixels obscured by the
    /// camera housing. Polling the global pointer keeps the exact-size compact
    /// notch hoverable without adding an invisible hit target around it.
    private func pollHover() {
        guard panel.isVisible, let screen = targetScreen else { return }
        let pointer = NSEvent.mouseLocation
        let visiblePanel = panel.frame.intersection(screen.frame)
        let pointerInside = visiblePanel.contains(pointer)

        if suppressHoverUntilExit {
            let compact = panelFrame(on: screen, expanded: false).intersection(screen.frame)
            if !compact.contains(pointer) { suppressHoverUntilExit = false }
            return
        }
        if revealUntil.map({ $0 > Date() }) == true {
            setExpanded(true)
            return
        }
        revealUntil = nil
        if pointerInside {
            setExpanded(true)
        } else {
            scheduleCollapse()
        }
    }

    private func refreshScreen(notify: Bool = false) {
        let previous = targetScreen != nil
        // Prefer the main screen when it has a usable camera housing, then fall
        // back to another attached notched display (normally the built-in panel).
        targetScreen = [NSScreen.main].compactMap { $0 }.first(where: Self.hasNotch)
            ?? NSScreen.screens.first(where: Self.hasNotch)
        if let screen = targetScreen, panel.isVisible {
            panel.setFrame(panelFrame(on: screen, expanded: isExpanded), display: true)
        } else if targetScreen == nil {
            hide(animated: false)
        }
        if notify, previous != (targetScreen != nil) {
            onAvailabilityChange?(targetScreen != nil)
        }
    }

    private static func hasNotch(_ screen: NSScreen) -> Bool {
        guard screen.safeAreaInsets.top > 0,
              let left = screen.auxiliaryTopLeftArea,
              let right = screen.auxiliaryTopRightArea else { return false }
        return !left.isEmpty && !right.isEmpty && right.minX > left.maxX
    }

    private func panelFrame(on screen: NSScreen, expanded: Bool) -> NSRect {
        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let housingWidth = max(1, (right?.minX ?? 0) - (left?.maxX ?? 0))
        let notchDepth = max(1, screen.safeAreaInsets.top)

        // Compact preserves the measured housing position and adds one small
        // black ear on the right for the Droid activity cue. Expanded recenters
        // to a consistent reading width so changing task text never makes it jitter.
        let indicatorWing: CGFloat = 28
        let width = expanded ? min(370, max(housingWidth + 150, 330)) : housingWidth + indicatorWing
        let visibleHeight = expanded ? notchDepth + 52 : notchDepth
        let hiddenTop: CGFloat = 14
        let originX = expanded
            ? round(screen.frame.midX - width / 2)
            : round(screen.frame.midX - housingWidth / 2)
        return NSRect(
            x: originX,
            y: screen.frame.maxY - visibleHeight,
            width: width,
            height: visibleHeight + hiddenTop)
    }
}

private final class NotchOverlayView: NSView {
    static let titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let detailFont = NSFont.systemFont(ofSize: 11.5, weight: .regular)
    static let timerFont = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)

    var onHoverChange: ((Bool) -> Void)?
    var onClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    private let rowView = NSView()
    private let compactIndicator = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let timerLabel = NSTextField(labelWithString: "")
    private let attentionIcon = NSImageView()
    private let labelClip = NSView()
    private let label = NSTextField(labelWithString: "")
    private let activityDot = CALayer()
    private var tracking: NSTrackingArea?
    private var marqueeWorkItem: DispatchWorkItem?
    private var isExpanded = false
    private var pulses = false
    private var pulseColor: NSColor?
    private var pulseConfigured = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = 16
        layer?.masksToBounds = true

        compactIndicator.wantsLayer = true
        compactIndicator.layer?.opacity = 1
        compactIndicator.imageScaling = .scaleProportionallyUpOrDown
        compactIndicator.contentTintColor = .white
        compactIndicator.setAccessibilityHidden(true)
        addSubview(compactIndicator)

        rowView.wantsLayer = true
        rowView.layer?.opacity = 0
        rowView.layer?.addSublayer(activityDot)
        addSubview(rowView)

        titleLabel.font = Self.titleFont
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 1
        rowView.addSubview(titleLabel)

        timerLabel.font = Self.timerFont
        timerLabel.textColor = NSColor.white.withAlphaComponent(0.68)
        timerLabel.alignment = .right
        rowView.addSubview(timerLabel)

        attentionIcon.imageScaling = .scaleProportionallyUpOrDown
        attentionIcon.image = NSImage(
            systemSymbolName: "exclamationmark.circle.fill",
            accessibilityDescription: "Approval needed")
        attentionIcon.isHidden = true
        rowView.addSubview(attentionIcon)

        labelClip.wantsLayer = true
        labelClip.layer?.masksToBounds = true
        rowView.addSubview(labelClip)

        label.font = Self.detailFont
        label.textColor = NSColor.white.withAlphaComponent(0.72)
        label.lineBreakMode = .byClipping
        label.maximumNumberOfLines = 1
        label.wantsLayer = true
        labelClip.addSubview(label)

        activityDot.cornerRadius = 4
        setAccessibilityRole(.button)
        setAccessibilityLabel("Droid activity")
        setAccessibilityHelp("Hover to show the active task. Click to open it. Right-click for options.")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { marqueeWorkItem?.cancel() }

    func configure(
        title: String,
        detail: String,
        elapsed: String?,
        indicator: NSImage?,
        toolTip: String?,
        color: NSColor,
        pulses: Bool,
        attention: Bool
    ) {
        let detailText = detail.isEmpty ? (attention ? "Approval needed" : "Working") : detail
        let elapsedText = elapsed ?? ""
        let titleChanged = titleLabel.stringValue != title
        let detailChanged = label.stringValue != detailText
        let elapsedChanged = timerLabel.stringValue != elapsedText
        let pulseChanged = !pulseConfigured
            || self.pulses != pulses
            || !(pulseColor?.isEqual(color) ?? false)
        self.pulses = pulses
        self.pulseColor = color
        pulseConfigured = true
        compactIndicator.image = indicator
        if titleChanged { titleLabel.stringValue = title }
        if elapsedChanged { timerLabel.stringValue = elapsedText }
        if detailChanged { label.stringValue = detailText }
        self.toolTip = toolTip
        setAccessibilityValue([title, detailText, elapsed].compactMap { $0 }.joined(separator: ", "))
        activityDot.backgroundColor = color.cgColor
        activityDot.isHidden = attention
        attentionIcon.isHidden = !attention
        attentionIcon.contentTintColor = color
        label.textColor = attention ? color : NSColor.white.withAlphaComponent(0.72)
        if pulseChanged { updatePulse() }
        if detailChanged {
            if isExpanded { scheduleMarquee(after: 0.08) }
        }
        if titleChanged || detailChanged || elapsedChanged { needsLayout = true }
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard expanded != isExpanded || !animated else { return }
        isExpanded = expanded
        marqueeWorkItem?.cancel()
        label.layer?.removeAnimation(forKey: "marquee")
        label.layer?.transform = CATransform3DIdentity

        let targetOpacity: Float = expanded ? 1 : 0
        let indicatorOpacity: Float = expanded ? 0 : 1
        if animated {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = rowView.layer?.presentation()?.opacity ?? rowView.layer?.opacity
            fade.toValue = targetOpacity
            fade.duration = expanded ? 0.18 : 0.10
            fade.timingFunction = CAMediaTimingFunction(name: expanded ? .easeOut : .easeIn)
            rowView.layer?.add(fade, forKey: "row-opacity")

            let indicatorFade = CABasicAnimation(keyPath: "opacity")
            indicatorFade.fromValue = compactIndicator.layer?.presentation()?.opacity
                ?? compactIndicator.layer?.opacity
            indicatorFade.toValue = indicatorOpacity
            indicatorFade.duration = expanded ? 0.10 : 0.14
            indicatorFade.timingFunction = CAMediaTimingFunction(name: expanded ? .easeIn : .easeOut)
            compactIndicator.layer?.add(indicatorFade, forKey: "indicator-opacity")
        }
        rowView.layer?.opacity = targetOpacity
        compactIndicator.layer?.opacity = indicatorOpacity
        layer?.borderWidth = expanded ? 0.5 : 0
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        updatePulse()
        if expanded { scheduleMarquee(after: animated ? 0.28 : 0) }
    }

    override func layout() {
        super.layout()
        let rowHeight: CGFloat = 38
        rowView.frame = NSRect(x: 16, y: 8, width: max(60, bounds.width - 32), height: rowHeight)
        compactIndicator.frame = NSRect(x: bounds.width - 23, y: 7, width: 16, height: 16)
        activityDot.frame = NSRect(x: 2, y: 25, width: 8, height: 8)
        attentionIcon.frame = NSRect(x: 0, y: 23, width: 12, height: 12)

        let timerText = timerLabel.stringValue as NSString
        let timerWidth = timerText.length == 0
            ? 0
            : ceil(timerText.size(withAttributes: [.font: Self.timerFont]).width) + 4
        timerLabel.isHidden = timerWidth == 0
        timerLabel.frame = NSRect(
            x: rowView.bounds.width - timerWidth,
            y: 20,
            width: timerWidth,
            height: 18)
        titleLabel.frame = NSRect(
            x: 18,
            y: 20,
            width: max(30, rowView.bounds.width - 18 - timerWidth - (timerWidth > 0 ? 8 : 0)),
            height: 18)

        labelClip.frame = NSRect(x: 18, y: 1, width: max(20, rowView.bounds.width - 18), height: 16)
        let textWidth = ceil((label.stringValue as NSString).size(withAttributes: [.font: Self.detailFont]).width)
        label.frame = NSRect(x: 0, y: 0, width: max(labelClip.bounds.width, textWidth), height: 16)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let next = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self)
        addTrackingArea(next)
        tracking = next
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }

    override func mouseDown(with event: NSEvent) {
        onHoverChange?(false)
        onClick?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onHoverChange?(false)
        onRightClick?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }

    private func updatePulse() {
        activityDot.removeAnimation(forKey: "activity-pulse")
        guard pulses, isExpanded else { return }
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.78, 1.0, 0.78]
        scale.keyTimes = [0, 0.5, 1]
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0.48, 1.0, 0.48]
        opacity.keyTimes = [0, 0.5, 1]
        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = 1.25
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        activityDot.add(group, forKey: "activity-pulse")
    }

    private func scheduleMarquee(after delay: TimeInterval) {
        marqueeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.startMarqueeIfNeeded() }
        marqueeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func startMarqueeIfNeeded() {
        guard isExpanded, labelClip.bounds.width > 0 else { return }
        label.layer?.removeAnimation(forKey: "marquee")
        label.layer?.transform = CATransform3DIdentity
        let textWidth = ceil((label.stringValue as NSString).size(withAttributes: [.font: Self.detailFont]).width)
        let distance = textWidth - labelClip.bounds.width
        guard distance > 1 else { return }

        let pause: Double = 1.1
        let travel = max(1.6, Double(distance) / 30.0)
        let duration = pause * 2 + travel * 2
        // Leave a few pixels of the trailing glyphs visible at the far edge;
        // landing exactly on the clip boundary can make Core Animation appear
        // blank for a frame on Retina displays.
        let endOffset = -max(0, distance - 8)
        let marquee = CAKeyframeAnimation(keyPath: "transform.translation.x")
        marquee.values = [0, 0, endOffset, endOffset, 0]
        marquee.keyTimes = [
            0,
            NSNumber(value: pause / duration),
            NSNumber(value: (pause + travel) / duration),
            NSNumber(value: (pause * 2 + travel) / duration),
            1,
        ]
        marquee.duration = duration
        marquee.repeatCount = .infinity
        marquee.calculationMode = .linear
        label.layer?.add(marquee, forKey: "marquee")
    }
}
