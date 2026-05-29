import AppKit
import LensCore
@preconcurrency import ScreenCaptureKit

/// Highlights the window under the pointer and captures it on click — the
/// "window only" path. Picks from the live `SCWindow` list so what's captured is
/// exactly the window content (ScreenCaptureKit), not a desktop-and-all grab.
@MainActor
final class WindowPickerController {
    private var window: PickerWindow?
    private var completion: ((SCWindow?) -> Void)?

    func begin(windows: [SCWindow], completion: @escaping (SCWindow?) -> Void) {
        self.completion = completion
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens[0]

        // Normal, on-screen, non-trivial windows only.
        let candidates = windows.filter {
            $0.isOnScreen && $0.windowLayer == 0 && $0.frame.width > 40 && $0.frame.height > 40
        }

        let win = PickerWindow(screen: screen, windows: candidates)
        win.onPick = { [weak self] picked in self?.deliver(picked) }
        win.onCancel = { [weak self] in self?.deliver(nil) }
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    private func deliver(_ picked: SCWindow?) {
        window?.orderOut(nil)
        window = nil
        let c = completion
        completion = nil
        c?(picked)
    }
}

private final class PickerWindow: NSWindow {
    var onPick: ((SCWindow?) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen, windows: [SCWindow]) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hasShadow = false
        acceptsMouseMovedEvents = true

        // Global-CG top-left origin of this screen (primary is 0,0).
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let cgOrigin = CGPoint(x: screen.frame.minX, y: primaryHeight - screen.frame.maxY)

        let view = PickerView(frame: NSRect(origin: .zero, size: screen.frame.size),
                              windows: windows, cgOrigin: cgOrigin)
        view.onPick = { [weak self] w in self?.onPick?(w) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
}

private final class PickerView: NSView {
    var onPick: ((SCWindow?) -> Void)?
    var onCancel: (() -> Void)?

    private let windows: [SCWindow]
    private let cgOrigin: CGPoint
    private var hovered: SCWindow?

    init(frame: NSRect, windows: [SCWindow], cgOrigin: CGPoint) {
        self.windows = windows
        self.cgOrigin = cgOrigin
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    /// Local (flipped) view point → global CG point.
    private func globalCG(_ local: NSPoint) -> CGPoint {
        CGPoint(x: cgOrigin.x + local.x, y: cgOrigin.y + local.y)
    }

    /// SCWindow frame (global CG) → local view rect.
    private func localRect(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX - cgOrigin.x, y: frame.minY - cgOrigin.y,
               width: frame.width, height: frame.height)
    }

    private func windowAt(_ local: NSPoint) -> SCWindow? {
        let g = globalCG(local)
        // Front-most first: SCShareableContent returns windows front-to-back.
        return windows.first { $0.frame.contains(g) }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        let w = windowAt(p)
        if w?.windowID != hovered?.windowID { hovered = w; needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        onPick?(windowAt(p))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds,
            options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.18).setFill()
        bounds.fill()
        guard let hovered else {
            drawPrompt("Move over a window, click to capture • Esc to cancel")
            return
        }
        let rect = localRect(hovered.frame)
        NSColor.clear.set()
        rect.fill(using: .copy)
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: rect); border.lineWidth = 2.5; border.stroke()
        if let title = hovered.owningApplication?.applicationName {
            drawLabel(title, in: rect)
        }
    }

    private func drawLabel(_ text: String, in rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size(); let pad: CGFloat = 8
        let box = CGRect(x: rect.midX - sz.width / 2 - pad, y: rect.midY - sz.height / 2 - pad,
                         width: sz.width + pad * 2, height: sz.height + pad * 2)
        NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
        s.draw(at: NSPoint(x: box.minX + pad, y: box.minY + pad))
    }

    private func drawPrompt(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: 60))
    }
}
