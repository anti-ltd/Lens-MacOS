import AppKit
import LensCore

/// A magnifier that follows the pointer over a frozen snapshot of the display,
/// showing zoomed pixels and the hex value under the crosshair. Click copies the
/// hex; Esc cancels. Sampling a single snapshot keeps it smooth — no per-frame
/// re-capture.
@MainActor
final class ColorLoupeController {
    private var window: LoupeWindow?
    private var completion: ((String?) -> Void)?

    func begin(displayImage: CGImage, screen: NSScreen, completion: @escaping (String?) -> Void) {
        self.completion = completion
        let rep = NSBitmapImageRep(cgImage: displayImage)
        let scale = CGFloat(displayImage.width) / max(screen.frame.width, 1)

        let win = LoupeWindow(screen: screen, rep: rep, scale: scale)
        win.onPick = { [weak self] hex in self?.deliver(hex) }
        win.onCancel = { [weak self] in self?.deliver(nil) }
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func deliver(_ hex: String?) {
        window?.orderOut(nil)
        window = nil
        let c = completion
        completion = nil
        c?(hex)
    }
}

private final class LoupeWindow: NSWindow {
    var onPick: ((String) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen, rep: NSBitmapImageRep, scale: CGFloat) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hasShadow = false
        acceptsMouseMovedEvents = true
        let view = LoupeView(frame: NSRect(origin: .zero, size: screen.frame.size), rep: rep, scale: scale)
        view.onPick = { [weak self] hex in self?.onPick?(hex) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
}

private final class LoupeView: NSView {
    var onPick: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let rep: NSBitmapImageRep
    private let scale: CGFloat
    private var cursor: NSPoint = .zero

    private let radius = 7          // sampled pixels each side of centre
    private let cell: CGFloat = 10  // on-screen size of one sampled pixel
    private let loupeOffset = CGPoint(x: 24, y: -24)

    init(frame: NSRect, rep: NSBitmapImageRep, scale: CGFloat) {
        self.rep = rep
        self.scale = scale
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) {
        cursor = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        cursor = convert(event.locationInWindow, from: nil)
        onPick?(hex(at: cursor))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }

    /// View point (top-left within screen) → rep pixel.
    private func pixel(at p: NSPoint) -> (Int, Int) {
        (Int(p.x * scale), Int(p.y * scale))
    }

    private func color(at p: NSPoint) -> NSColor {
        let (px, py) = pixel(at: p)
        let cx = min(max(px, 0), rep.pixelsWide - 1)
        let cy = min(max(py, 0), rep.pixelsHigh - 1)
        return rep.colorAt(x: cx, y: cy)?.usingColorSpace(.sRGB) ?? .black
    }

    private func hex(at p: NSPoint) -> String {
        let c = color(at: p)
        return String(format: "#%02X%02X%02X",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    override func draw(_ dirtyRect: NSRect) {
        let span = CGFloat(radius * 2 + 1) * cell
        let loupeRect = CGRect(x: cursor.x + loupeOffset.x, y: cursor.y + loupeOffset.y,
                               width: span, height: span)

        NSGraphicsContext.current?.cgContext.saveGState()
        let clip = NSBezierPath(ovalIn: loupeRect)
        clip.addClip()
        // Zoomed pixel grid.
        for dy in -radius...radius {
            for dx in -radius...radius {
                let sample = NSPoint(x: cursor.x + CGFloat(dx), y: cursor.y + CGFloat(dy))
                color(at: sample).setFill()
                let r = CGRect(x: loupeRect.minX + CGFloat(dx + radius) * cell,
                               y: loupeRect.minY + CGFloat(dy + radius) * cell,
                               width: cell, height: cell)
                r.fill()
            }
        }
        NSGraphicsContext.current?.cgContext.restoreGState()

        // Centre cell highlight + loupe ring.
        NSColor.white.setStroke()
        let centre = CGRect(x: loupeRect.minX + CGFloat(radius) * cell,
                            y: loupeRect.minY + CGFloat(radius) * cell, width: cell, height: cell)
        let box = NSBezierPath(rect: centre); box.lineWidth = 1; box.stroke()
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let ring = NSBezierPath(ovalIn: loupeRect); ring.lineWidth = 2; ring.stroke()

        // Hex read-out below the loupe.
        let value = hex(at: cursor)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let s = NSAttributedString(string: value, attributes: attrs)
        let sz = s.size(); let pad: CGFloat = 6
        let labelBox = CGRect(x: loupeRect.midX - sz.width / 2 - pad, y: loupeRect.maxY + 6,
                              width: sz.width + pad * 2, height: sz.height + pad)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: labelBox, xRadius: 4, yRadius: 4).fill()
        s.draw(at: NSPoint(x: labelBox.minX + pad, y: labelBox.minY + pad / 2))
    }
}
