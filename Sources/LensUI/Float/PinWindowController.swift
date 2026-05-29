import AppKit

/// Pins an image as a borderless, always-on-top, draggable window — the
/// "keep this reference floating" workflow. Multiple pins coexist; each one
/// owns itself until closed (⌘W / Esc) or dropped.
@MainActor
enum PinWindowController {
    private static var pins: [PinWindow] = []

    static func pin(_ image: CGImage) {
        let maxW: CGFloat = 480
        let scale = CGFloat(image.width) > maxW ? maxW / CGFloat(image.width) : 1
        let size = NSSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)

        let origin = NSPoint(
            x: (NSScreen.main?.frame.midX ?? 400) - size.width / 2,
            y: (NSScreen.main?.frame.midY ?? 300) - size.height / 2
        )
        let win = PinWindow(contentRect: NSRect(origin: origin, size: size))
        let view = NSImageView(frame: NSRect(origin: .zero, size: size))
        view.image = NSImage(cgImage: image, size: size)
        view.imageScaling = .scaleAxesIndependently
        view.wantsLayer = true
        view.layer?.cornerRadius = 6
        view.layer?.masksToBounds = true
        win.contentView = view
        win.onClose = { pins.removeAll { $0 === win } }
        pins.append(win)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func closeAll() {
        pins.forEach { $0.close() }
        pins.removeAll()
    }
}

final class PinWindow: NSWindow {
    var onClose: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        level = .floating
        isMovableByWindowBackground = true
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        // Esc, or ⌘W, closes the pin.
        if event.keyCode == 53 || (event.keyCode == 13 && event.modifierFlags.contains(.command)) {
            close()
        } else {
            super.keyDown(with: event)
        }
    }

    override func close() {
        onClose?()
        super.close()
    }
}
