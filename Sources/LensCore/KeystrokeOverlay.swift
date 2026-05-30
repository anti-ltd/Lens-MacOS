import AppKit
import CoreImage
import CoreGraphics

/// Keystroke-overlay tuning. Renders pressed shortcuts as keycap chips in the
/// lower third — the "see the shortcut" caption common in app demos.
public struct KeystrokeStyle: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Only show combos with a modifier (⌘/⌃/⌥/⇧); skips plain typing.
    public var shortcutsOnly: Bool
    /// Size multiplier for the chips.
    public var size: CGFloat
    /// Seconds a chord stays on screen.
    public var hold: Double

    public init(enabled: Bool = false, shortcutsOnly: Bool = true, size: CGFloat = 1.0, hold: Double = 1.2) {
        self.enabled = enabled
        self.shortcutsOnly = shortcutsOnly
        self.size = size
        self.hold = hold
    }
}

/// Turns the recorded key track into timed keycap captions.
@available(macOS 14.0, *)
final class KeystrokePlan {
    struct Caption { let start: Double; let end: Double; let chips: [String] }
    private let captions: [Caption]

    private static let shift = 1 << 17, control = 1 << 18, option = 1 << 19, command = 1 << 20

    init(events: RecordingEvents, style: KeystrokeStyle) {
        var out: [Caption] = []
        for k in events.keys where k.down {
            let hasMods = k.modifiers & (Self.shift | Self.control | Self.option | Self.command) != 0
            if style.shortcutsOnly && !hasMods { continue }
            out.append(Caption(start: k.t, end: k.t + style.hold, chips: Self.chips(modifiers: k.modifiers, keyCode: k.keyCode)))
        }
        captions = out
    }

    static func chips(modifiers: Int, keyCode: Int) -> [String] {
        var g: [String] = []
        if modifiers & control != 0 { g.append("⌃") }
        if modifiers & option != 0 { g.append("⌥") }
        if modifiers & shift != 0 { g.append("⇧") }
        if modifiers & command != 0 { g.append("⌘") }
        g.append(Keycodes.label(for: UInt16(keyCode)))
        return g
    }

    /// The active caption at `t` (latest still on screen) with a fade alpha.
    func active(at t: Double) -> (chips: [String], alpha: CGFloat)? {
        guard let c = captions.last(where: { t >= $0.start && t <= $0.end }) else { return nil }
        let fadeIn = 0.08, fadeOut = 0.25
        let a: Double
        if t - c.start < fadeIn { a = (t - c.start) / fadeIn }
        else if c.end - t < fadeOut { a = (c.end - t) / fadeOut }
        else { a = 1 }
        return (c.chips, CGFloat(max(0, min(1, a))))
    }
}

/// Draws a row of keycap chips into an image. Cached by (caption, height) since
/// a chord persists across many frames.
@available(macOS 14.0, *)
final class KeystrokeArt {
    private var cacheKey = ""
    private var cached: CIImage?

    /// A row of dark keycap chips with light glyphs. Uses a genuinely flipped
    /// focus so the text isn't upside down.
    func image(for chips: [String], heightPx: CGFloat) -> CIImage? {
        let key = "\(Int(heightPx))|\(chips.joined(separator: "+"))"
        if key == cacheKey, let cached { return cached }

        let h = max(16, heightPx)
        let font = NSFont.systemFont(ofSize: h * 0.52, weight: .semibold)
        let gap = h * 0.16
        let pad = h * 0.32
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]

        let widths = chips.map { chip -> CGFloat in
            max(h, (chip as NSString).size(withAttributes: attrs).width + pad * 2)
        }
        let totalW = widths.reduce(0, +) + gap * CGFloat(max(0, chips.count - 1))
        guard totalW > 0 else { return nil }

        let canvas = NSImage(size: NSSize(width: ceil(totalW), height: ceil(h)))
        canvas.lockFocusFlipped(true)
        var x: CGFloat = 0
        for (i, chip) in chips.enumerated() {
            let w = widths[i]
            let rect = NSRect(x: x, y: 0, width: w, height: h)
            NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 0.95).setFill()
            NSColor.white.withAlphaComponent(0.18).setStroke()
            let cap = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: h * 0.22, yRadius: h * 0.22)
            cap.fill(); cap.lineWidth = 1; cap.stroke()
            let s = NSAttributedString(string: chip, attributes: attrs)
            let sz = s.size()
            s.draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2))
            x += w + gap
        }
        canvas.unlockFocus()

        guard let cg = canvas.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let img = CIImage(cgImage: cg)
        cacheKey = key; cached = img
        return img
    }
}
