import Cocoa

/// Spinner presets extracted from Droid CLI (`tuiSpinner` catalog in the `droid` binary).
/// Primary menu-bar look: three horizontal dots (drawn, not SVG) — matches common loading UI.
enum DroidSpinners {
    struct Preset {
        let name: String
        let intervalMs: Double
        let frames: [String]
        var fps: Double { 1000.0 / intervalMs }
    }

    /// Three-dot pulse (● ○ ○ → ○ ● ○ → ○ ○ ●). Default Droid status-bar animation.
    /// Drawn as vector circles into NSImage — not SVG files.
    static let threeDotsFPS: Double = 4.5  // ~220ms per frame, calm menu-bar pace

    /// Classic braille spinner from Droid TUI `dots` (includes ⠏ as a frame).
    static let dots = Preset(
        name: "dots",
        intervalMs: 80,
        frames: ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"])

    /// Explicitly used by Droid for streaming status (`preset:"dots10"`).
    static let dots10 = Preset(
        name: "dots10",
        intervalMs: 80,
        frames: ["⢄", "⢂", "⢁", "⡁", "⡈", "⡐", "⡠"])

    /// Block braille (`dots2` in Droid).
    static let dots2 = Preset(
        name: "dots2",
        intervalMs: 80,
        frames: ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"])

    /// Pulse in/out (`breathe`).
    static let breathe = Preset(
        name: "breathe",
        intervalMs: 100,
        frames: ["⠀", "⠂", "⠌", "⡑", "⢕", "⢝", "⣫", "⣟", "⣿", "⣟", "⣫", "⢝", "⢕", "⡑", "⠌", "⠂", "⠀"])

    /// Orbiting braille (`orbit`).
    static let orbit = Preset(
        name: "orbit",
        intervalMs: 100,
        frames: ["⠃", "⠉", "⠘", "⠰", "⢠", "⣀", "⡄", "⠆"])

    /// Circle quarters (`circleHalves`) — 50ms in CLI, slowed a bit for the menu bar.
    static let circle = Preset(
        name: "circle",
        intervalMs: 80,
        frames: ["◐", "◓", "◑", "◒"])

    static let all: [Preset] = [dots, dots10, dots2, breathe, orbit, circle]

    static func preset(named name: String) -> Preset? {
        all.first { $0.name == name }
    }

    // MARK: - Three horizontal dots (menu-bar default)

    /// Build one frame: `active` index is solid filled; the other two are ring outlines.
    /// Looks like: ● ○ ○  /  ○ ● ○  /  ○ ○ ●
    static func threeDotFrame(active: Int, color: NSColor?, size: CGFloat = 18) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let fill = color ?? NSColor.labelColor
            let n: CGFloat = 3
            let diameter = size * 0.28
            let gap = size * 0.10
            let totalW = n * diameter + (n - 1) * gap
            let startX = (rect.width - totalW) / 2
            let cy = rect.midY

            for i in 0..<3 {
                let cx = startX + CGFloat(i) * (diameter + gap) + diameter / 2
                let r = NSRect(x: cx - diameter / 2, y: cy - diameter / 2,
                               width: diameter, height: diameter)
                let path = NSBezierPath(ovalIn: r)
                if i == active % 3 {
                    fill.setFill()
                    path.fill()
                } else {
                    // Hollow ring — matches the reference “three dots” loading look
                    fill.withAlphaComponent(0.35).setStroke()
                    path.lineWidth = max(1.0, diameter * 0.18)
                    path.stroke()
                }
            }
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }

    /// All three-dot animation frames (active index 0, 1, 2).
    static func threeDotFrames(color: NSColor?) -> [NSImage] {
        (0..<3).map { threeDotFrame(active: $0, color: color, size: 18) }
    }

    /// Resting icon: all three dots as soft rings (or middle filled lightly).
    static func threeDotResting(color: NSColor?) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let fill = color ?? NSColor.labelColor
            let n: CGFloat = 3
            let diameter: CGFloat = 18 * 0.28
            let gap: CGFloat = 18 * 0.10
            let totalW = n * diameter + (n - 1) * gap
            let startX = (rect.width - totalW) / 2
            let cy = rect.midY
            for i in 0..<3 {
                let cx = startX + CGFloat(i) * (diameter + gap) + diameter / 2
                let r = NSRect(x: cx - diameter / 2, y: cy - diameter / 2,
                               width: diameter, height: diameter)
                let path = NSBezierPath(ovalIn: r)
                fill.withAlphaComponent(0.45).setStroke()
                path.lineWidth = max(1.0, diameter * 0.18)
                path.stroke()
            }
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }
}

/// Startup logo frames extracted from Droid CLI `FullScreenAnimation` (`Rai` array).
/// Each frame is 24 lines × 60 columns of ASCII/block art; we subsample for the menu bar.
enum DroidLogoFrames {
    /// Densest frame index (the “DROID” wordmark) — used as the resting icon.
    static let restingIndex = 38

    /// Step through every Nth animation frame so the 44-frame splash fits a menu-bar cycle.
    static let sampleStep = 2

    /// Loaded lazily from bundled JSON (copied into the app Resources at build time).
    static let frames: [[String]] = {
        let candidates = [
            Bundle.main.path(forResource: "droid-logo-frames", ofType: "json"),
            (NSHomeDirectory() as NSString).appendingPathComponent(
                "droid-status-bar/assets/droid-logo-frames.json"),
        ]
        for path in candidates.compactMap({ $0 }) {
            if let data = FileManager.default.contents(atPath: path),
               let arr = try? JSONSerialization.jsonObject(with: data) as? [[String]],
               !arr.isEmpty {
                return arr
            }
        }
        return []
    }()

    static var sampleIndices: [Int] {
        guard !frames.isEmpty else { return [] }
        var idx: [Int] = []
        var i = 0
        while i < frames.count {
            idx.append(i)
            i += sampleStep
        }
        if idx.last != frames.count - 1 { idx.append(frames.count - 1) }
        return idx
    }

    /// Rasterize one ASCII frame into an 18pt menu-bar image (cropped to non-empty bounds).
    static func image(for lines: [String], color: NSColor?, pointSize: CGFloat = 18) -> NSImage {
        let nonEmpty = lines.filter { $0.contains(where: { $0 != " " }) }
        guard !nonEmpty.isEmpty else {
            return NSImage(size: NSSize(width: pointSize, height: pointSize))
        }
        // Tight crop: drop empty left/right padding.
        var minX = Int.max, maxX = 0
        for line in nonEmpty {
            if let first = line.firstIndex(where: { $0 != " " }),
               let last = line.lastIndex(where: { $0 != " " }) {
                minX = min(minX, line.distance(from: line.startIndex, to: first))
                maxX = max(maxX, line.distance(from: line.startIndex, to: last))
            }
        }
        if minX == Int.max { minX = 0 }
        let cropped = nonEmpty.map { line -> String in
            let start = min(minX, line.count)
            let end = min(maxX + 1, line.count)
            if start >= end { return "" }
            let a = line.index(line.startIndex, offsetBy: start)
            let b = line.index(line.startIndex, offsetBy: end)
            return String(line[a..<b])
        }

        let joined = cropped.joined(separator: "\n") as NSString
        // Size so the art fills ~pointSize height.
        let fontSize = max(1.5, pointSize / CGFloat(max(cropped.count, 1)) * 1.15)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color ?? NSColor.labelColor,
        ]
        let textSize = joined.size(withAttributes: attrs)
        let scale = min(pointSize / max(textSize.width, 1), pointSize / max(textSize.height, 1))
        let w = max(pointSize, ceil(textSize.width * scale))
        let h = pointSize
        let img = NSImage(size: NSSize(width: w, height: h), flipped: false) { rect in
            let dw = textSize.width * scale
            let dh = textSize.height * scale
            let origin = NSPoint(x: (rect.width - dw) / 2, y: (rect.height - dh) / 2)
            let scaled = NSAffineTransform()
            scaled.translateX(by: origin.x, yBy: origin.y)
            scaled.scale(by: scale)
            scaled.concat()
            joined.draw(at: .zero, withAttributes: attrs)
            return true
        }
        img.isTemplate = (color == nil)
        return img
    }
}
