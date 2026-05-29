import AppKit

/// Renders `AppIcon.iconset` programmatically: a full-bleed continuous-rounded
/// squircle with the house gradient and a white aperture glyph. `make icon`
/// runs `Lens --icon <dir>` then `iconutil`s the folder into `AppIcon.icns`.
public enum AppIconRenderer {
    // Apple's icon corner ratio — full-bleed continuous squircle.
    private static let cornerRatio: CGFloat = 0.2237

    public static func run(directory: String) {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // (point size, scale) → filename, per Apple's iconset spec.
        let specs: [(Int, Int)] = [
            (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
            (256, 1), (256, 2), (512, 1), (512, 2),
        ]
        for (pt, scale) in specs {
            let px = pt * scale
            guard let image = render(size: px) else { continue }
            let name = scale == 1 ? "icon_\(pt)x\(pt).png" : "icon_\(pt)x\(pt)@2x.png"
            write(image, to: dir.appendingPathComponent(name))
        }
    }

    private static func render(size px: Int) -> NSImage? {
        let s = CGFloat(px)
        let image = NSImage(size: NSSize(width: s, height: s))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: s, height: s)
        let radius = s * cornerRatio
        let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        squircle.addClip()

        // House gradient (blue → violet), matching the brand accents.
        let from = NSColor(srgbRed: 0x5B / 255, green: 0x8C / 255, blue: 0xFF / 255, alpha: 1)
        let to   = NSColor(srgbRed: 0xA8 / 255, green: 0x55 / 255, blue: 0xF7 / 255, alpha: 1)
        NSGradient(starting: from, ending: to)?.draw(in: rect, angle: -90)

        // Aperture glyph centred, sized to ~62% of the icon.
        let glyphSize = s * 0.62
        let config = NSImage.SymbolConfiguration(pointSize: glyphSize, weight: .semibold)
        if let glyph = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: nil)?
            .withSymbolConfiguration(config) {
            let tinted = tint(glyph, with: .white)
            let gw = tinted.size.width, gh = tinted.size.height
            tinted.draw(in: NSRect(x: (s - gw) / 2, y: (s - gh) / 2, width: gw, height: gh))
        }
        return image
    }

    private static func tint(_ image: NSImage, with color: NSColor) -> NSImage {
        let out = NSImage(size: image.size)
        out.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: image.size)
        image.draw(in: rect)
        rect.fill(using: .sourceAtop)
        out.unlockFocus()
        out.isTemplate = false
        return out
    }

    private static func write(_ image: NSImage, to url: URL) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url)
    }
}
