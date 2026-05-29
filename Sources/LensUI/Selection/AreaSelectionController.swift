import AppKit
import LensCore
@preconcurrency import ScreenCaptureKit

/// Presents a full-screen dimmed overlay on the display under the pointer and
/// lets the user drag out a selection. When a preset pins an aspect ratio the
/// rectangle is locked to it while dragging — the "set the frame once" promise.
/// Resolves to the `SCDisplay` + pixel crop the engine needs.
@MainActor
final class AreaSelectionController {
    struct Result {
        let display: SCDisplay
        let cropPixels: CGRect       // top-left, display pixel space
        let globalCenter: CGPoint    // top-left global CG points (for scrolling)
    }

    private let aspect: CGFloat?
    private let prompt: String
    private var window: SelectionWindow?
    private var completion: ((Result?) -> Void)?

    init(aspect: CGFloat?, prompt: String = "Drag to select • Esc to cancel") {
        self.aspect = aspect
        self.prompt = prompt
    }

    func begin(completion: @escaping (Result?) -> Void) {
        self.completion = completion
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
            ?? NSScreen.main ?? NSScreen.screens[0]

        let win = SelectionWindow(screen: screen, aspect: aspect, prompt: prompt)
        win.onFinish = { [weak self] selectionPoints in
            self?.resolve(selectionPoints, screen: screen)
        }
        win.onCancel = { [weak self] in self?.deliver(nil) }
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    /// `selectionPoints` is in the overlay view's top-left coords (== display
    /// points). Resolve the SCDisplay by display id, then scale to pixels.
    private func resolve(_ selectionPoints: CGRect, screen: NSScreen) {
        guard selectionPoints.width >= 2, selectionPoints.height >= 2 else { deliver(nil); return }
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
        Task {
            do {
                let content = try await CaptureEngine.shareableContent()
                let display = content.displays.first { $0.displayID == displayID } ?? content.displays.first
                guard let display else { self.deliver(nil); return }
                let scale = CaptureEngine.scale(for: display)
                let cropPixels = CGRect(
                    x: selectionPoints.minX * scale,
                    y: selectionPoints.minY * scale,
                    width: selectionPoints.width * scale,
                    height: selectionPoints.height * scale
                )
                let globalCenter = CGPoint(
                    x: display.frame.minX + selectionPoints.midX,
                    y: display.frame.minY + selectionPoints.midY
                )
                self.deliver(Result(display: display, cropPixels: cropPixels, globalCenter: globalCenter))
            } catch {
                self.deliver(nil)
            }
        }
    }

    private func deliver(_ result: Result?) {
        window?.orderOut(nil)
        window = nil
        let c = completion
        completion = nil
        c?(result)
    }
}

/// Borderless overlay covering one display. Hosts the drag view and captures the
/// Escape key. Can become key so keyDown reaches it.
private final class SelectionWindow: NSWindow {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    init(screen: NSScreen, aspect: CGFloat?, prompt: String) {
        super.init(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .screenSaver
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        hasShadow = false
        let view = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), aspect: aspect, prompt: prompt)
        view.onFinish = { [weak self] rect in self?.onFinish?(rect) }
        view.onCancel = { [weak self] in self?.onCancel?() }
        contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The drag surface. Flipped (top-left origin) so reported rects map straight to
/// display points. Dims everything, punches out the live selection, and draws a
/// dimension read-out.
private final class SelectionView: NSView {
    var onFinish: ((CGRect) -> Void)?
    var onCancel: (() -> Void)?

    private let aspect: CGFloat?
    private let prompt: String
    private var start: CGPoint?
    private var selection: CGRect = .zero

    init(frame: NSRect, aspect: CGFloat?, prompt: String) {
        self.aspect = aspect
        self.prompt = prompt
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        selection = .zero
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = convert(event.locationInWindow, from: nil)
        selection = rect(from: start, to: p)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let final = selection
        if final.width >= 2, final.height >= 2 {
            onFinish?(final)
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } // Escape
    }

    /// Build the selection rect, ratio-locked when an aspect is set. Drag
    /// direction is preserved so the box grows toward the pointer.
    private func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        var w = b.x - a.x
        var h = b.y - a.y
        if let aspect, aspect > 0 {
            // Lock height to width; keep the sign of the vertical drag.
            let signH: CGFloat = h < 0 ? -1 : 1
            h = signH * abs(w) / aspect
        }
        let originX = w < 0 ? a.x + w : a.x
        let originY = h < 0 ? a.y + h : a.y
        return CGRect(x: originX, y: originY, width: abs(w), height: abs(h)).intersection(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        // Dim everything, then clear the selection so it reads as a window.
        NSColor.black.withAlphaComponent(0.35).setFill()
        bounds.fill()
        if selection.width > 0, selection.height > 0 {
            NSColor.clear.set()
            selection.fill(using: .copy)
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: selection)
            border.lineWidth = 1.5
            border.stroke()
            drawLabel("\(Int(selection.width)) × \(Int(selection.height))", near: selection)
        } else {
            drawCentredPrompt(prompt)
        }
    }

    private func drawLabel(_ text: String, near rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        let pad: CGFloat = 6
        let bx = min(rect.minX, bounds.width - sz.width - pad * 2)
        let by = max(rect.minY - sz.height - pad * 2, 0)
        let box = CGRect(x: bx, y: by, width: sz.width + pad * 2, height: sz.height + pad * 2)
        NSColor.black.withAlphaComponent(0.6).setFill()
        NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4).fill()
        s.draw(at: NSPoint(x: box.minX + pad, y: box.minY + pad))
    }

    private func drawCentredPrompt(_ text: String) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor.white.withAlphaComponent(0.9),
        ]
        let s = NSAttributedString(string: text, attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: (bounds.width - sz.width) / 2, y: (bounds.height - sz.height) / 2))
    }
}
