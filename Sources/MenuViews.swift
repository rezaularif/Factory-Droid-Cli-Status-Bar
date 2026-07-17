import Cocoa

/// Custom toggle that renders correctly inside NSMenu (NSSwitch greys out under vibrant menus).
final class ToggleView: NSView {
    static let w: CGFloat = 33, h: CGFloat = 16
    private let track = CALayer()
    private let knob = CALayer()
    private var lastToggle = Date.distantPast
    private var hovered = false
    var isOn: Bool { didSet { updateState(animated: true) } }
    var onToggle: ((Bool) -> Void)?

    init(isOn: Bool) {
        self.isOn = isOn
        super.init(frame: NSRect(x: 0, y: 0, width: ToggleView.w, height: ToggleView.h))
        layer = CALayer()
        wantsLayer = true
        track.frame = bounds
        track.cornerRadius = bounds.height / 2
        layer?.addSublayer(track)
        let kh = bounds.height - 4, kw = kh + 3
        knob.bounds = CGRect(x: 0, y: 0, width: kw, height: kh)
        knob.cornerRadius = kh / 2
        knob.backgroundColor = NSColor.white.cgColor
        layer?.addSublayer(knob)
        updateState(animated: false)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: NSSize { NSSize(width: ToggleView.w, height: ToggleView.h) }

    private func knobCenter() -> CGPoint {
        let kw = knob.bounds.width
        return CGPoint(x: isOn ? bounds.width - kw / 2 - 2 : kw / 2 + 2, y: bounds.height / 2)
    }

    private func trackColor() -> CGColor {
        if isOn {
            let accent = NSColor.controlAccentColor
            return (hovered ? (accent.blended(withFraction: 0.10, of: .white) ?? accent) : accent).cgColor
        }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let base: CGFloat = dark ? 1.0 : 0.0
        let alpha: CGFloat = (dark ? 0.30 : 0.34) + (hovered ? 0.10 : 0)
        return NSColor(white: base, alpha: alpha).cgColor
    }

    private func updateState(animated: Bool) {
        let toColor = trackColor()
        let toPos = knobCenter()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if animated {
            let spring = CASpringAnimation(keyPath: "position")
            spring.fromValue = NSValue(point: knob.presentation()?.position ?? knob.position)
            spring.toValue = NSValue(point: toPos)
            spring.damping = 16; spring.stiffness = 260; spring.mass = 1; spring.initialVelocity = 0
            spring.duration = spring.settlingDuration
            knob.add(spring, forKey: "position")
            let col = CABasicAnimation(keyPath: "backgroundColor")
            col.fromValue = track.presentation()?.backgroundColor ?? track.backgroundColor
            col.toValue = toColor
            col.duration = 0.2
            track.add(col, forKey: "backgroundColor")
        }
        knob.position = toPos
        track.backgroundColor = toColor
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateState(animated: false)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; updateState(animated: false) }
    override func mouseExited(with event: NSEvent) { hovered = false; updateState(animated: false) }

    override func mouseDown(with event: NSEvent) {
        guard Date().timeIntervalSince(lastToggle) > 0.1 else { return }
        lastToggle = Date()
        isOn.toggle()
        onToggle?(isOn)
    }
}

/// Session row: [icon] name · branch   timer  [CLI/APP pill]
///                    live state · task detail
final class SessionRowView: NSView {
    let id: String
    var onClick: (() -> Void)?
    private let iconView = NSImageView()
    private let spinner = NSProgressIndicator()
    private let nameField = NSTextField(labelWithString: "")
    private let activityField = NSTextField(labelWithString: "")
    private let timerField = NSTextField(labelWithString: "")
    private let pillView = NSImageView()
    private let pad: CGFloat = 14, iconSize: CGFloat = 16, rowH: CGFloat = 40
    private let highlightView = NSVisualEffectView()
    private var hovered = false
    private var iconBaseTint: NSColor?
    private var pillNormal: NSImage?, pillSelected: NSImage?
    private var nameText = "", activityText = "", branchText = ""

    init(id: String, width: CGFloat) {
        self.id = id
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: rowH))
        autoresizingMask = [.width]
        highlightView.material = .selection
        highlightView.state = .active
        highlightView.isEmphasized = true
        highlightView.wantsLayer = true
        highlightView.layer?.cornerRadius = 5
        highlightView.isHidden = true
        addSubview(highlightView)

        iconView.frame = NSRect(x: pad, y: (rowH - iconSize) / 2, width: iconSize, height: iconSize)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.autoresizingMask = [.maxXMargin]
        addSubview(iconView)

        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isIndeterminate = true
        spinner.isDisplayedWhenStopped = false
        spinner.frame = iconView.frame
        spinner.autoresizingMask = [.maxXMargin]
        spinner.isHidden = true
        addSubview(spinner)

        nameField.font = .menuFont(ofSize: 0)
        nameField.textColor = .labelColor
        nameField.lineBreakMode = .byTruncatingTail
        nameField.frame = NSRect(x: pad + iconSize + 8, y: rowH - 19, width: 160, height: 16)
        nameField.autoresizingMask = [.maxXMargin]
        addSubview(nameField)

        activityField.font = NSFont.systemFont(
            ofSize: max(10, NSFont.menuFont(ofSize: 0).pointSize - 2))
        activityField.textColor = .secondaryLabelColor
        activityField.lineBreakMode = .byTruncatingTail
        activityField.frame = NSRect(
            x: pad + iconSize + 8, y: 3, width: 160, height: 14)
        activityField.autoresizingMask = [.maxXMargin]
        addSubview(activityField)

        timerField.font = NSFont.monospacedSystemFont(
            ofSize: NSFont.menuFont(ofSize: 0).pointSize - 2, weight: .regular)
        timerField.textColor = .secondaryLabelColor
        timerField.alignment = .right
        timerField.autoresizingMask = [.minXMargin]
        addSubview(timerField)

        pillView.imageScaling = .scaleNone
        pillView.autoresizingMask = [.minXMargin]
        addSubview(pillView)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(icon: NSImage?, iconTint: NSColor?, spinning: Bool, name: String, activity: String, branch: String,
                   timer: String?, pillNormal: NSImage?, pillSelected: NSImage?,
                   pillInset: CGFloat, timerGap: CGFloat) {
        let w = bounds.width
        iconView.image = icon
        iconBaseTint = iconTint
        iconView.contentTintColor = hovered ? .white : iconTint
        if spinning {
            iconView.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
        } else {
            spinner.stopAnimation(nil)
            spinner.isHidden = true
            iconView.isHidden = false
        }
        nameText = name
        activityText = activity
        branchText = branch
        renderName()
        activityField.stringValue = activityText
        self.pillNormal = pillNormal
        self.pillSelected = pillSelected
        let pill = hovered ? pillSelected : pillNormal
        var pillLeft = w - pillInset
        if let pill = pill {
            pillView.isHidden = false
            pillView.image = pill
            pillView.frame = NSRect(
                x: w - pillInset - pill.size.width, y: rowH - 20.5,
                width: pill.size.width, height: pill.size.height)
            pillLeft = pillView.frame.minX
        } else {
            pillView.isHidden = true
        }
        if let timer = timer {
            timerField.isHidden = false
            timerField.stringValue = timer
            let font = timerField.font ?? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            let tw = ceil(timer.size(withAttributes: [.font: font]).width) + 2
            let nf = nameField.font ?? NSFont.menuFont(ofSize: 0)
            let baseline = { (f: NSFont) in (16 - (f.ascender - f.descender)) / 2 - f.descender }
            let dy = baseline(nf) - baseline(font)
            timerField.frame = NSRect(
                x: pillLeft - timerGap - tw, y: rowH - 19 + dy, width: tw, height: 16)
        } else {
            timerField.isHidden = true
        }
        let nameRight = timerField.isHidden
            ? (pillView.isHidden ? w - pillInset : pillView.frame.minX - 8)
            : timerField.frame.minX - 8
        let nameLeft = pad + iconSize + 8
        nameField.frame = NSRect(
            x: nameLeft, y: rowH - 19,
            width: max(40, nameRight - nameLeft), height: 16)
        let activityRight = timerField.isHidden
            ? (pillView.isHidden ? w - pillInset : pillView.frame.minX - 8)
            : timerField.frame.minX - 8
        activityField.frame = NSRect(
            x: nameLeft, y: 3,
            width: max(40, activityRight - nameLeft), height: 14)
    }

    private func renderName() {
        let font = nameField.font ?? NSFont.menuFont(ofSize: 0)
        if branchText.isEmpty {
            nameField.attributedStringValue = NSAttributedString(
                string: nameText, attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            return
        }
        let s = NSMutableAttributedString(
            string: nameText,
            attributes: [.font: font, .foregroundColor: NSColor.labelColor])
        s.append(NSAttributedString(
            string: " · " + branchText,
            attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
        nameField.attributedStringValue = s
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self))
    }
    override func mouseEntered(with event: NSEvent) {
        hovered = true
        highlightView.isHidden = false
        iconView.contentTintColor = .white
        if !pillView.isHidden { pillView.image = pillSelected }
    }
    override func mouseExited(with event: NSEvent) {
        hovered = false
        highlightView.isHidden = true
        iconView.contentTintColor = iconBaseTint
        if !pillView.isHidden { pillView.image = pillNormal }
    }
    override func layout() {
        super.layout()
        highlightView.frame = bounds.insetBy(dx: 5, dy: 0)
    }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
