import AppKit

/// Lightweight, non-blocking confirmations: the shutter sound, a transient text
/// toast, and a corner thumbnail flash after a capture lands.
@MainActor
enum CaptureFeedback {
    private static var huds: [NSWindow] = []

    static func shutter() {
        NSSound(named: "Pop")?.play()
    }

    static func toast(_ text: String) {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.sizeToFit()

        let pad: CGFloat = 14
        let size = NSSize(width: label.frame.width + pad * 2, height: label.frame.height + pad)
        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.8).cgColor
        container.layer?.cornerRadius = 10
        label.frame.origin = NSPoint(x: pad, y: pad / 2)
        container.addSubview(label)

        present(container, anchor: .bottomCenter, duration: 1.6)
    }

    static func flash(_ image: CGImage) {
        let thumbW: CGFloat = 220
        let aspect = CGFloat(image.height) / CGFloat(max(image.width, 1))
        let size = NSSize(width: thumbW, height: min(thumbW * aspect, 220))
        let view = NSImageView(frame: NSRect(origin: .zero, size: size))
        view.image = NSImage(cgImage: image, size: size)
        view.imageScaling = .scaleProportionallyUpOrDown
        view.wantsLayer = true
        view.layer?.cornerRadius = 8
        view.layer?.masksToBounds = true
        view.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        view.layer?.borderWidth = 1
        present(view, anchor: .bottomRight, duration: 1.2)
    }

    // MARK: - HUD plumbing

    private enum Anchor { case bottomCenter, bottomRight }

    private static func present(_ content: NSView, anchor: Anchor, duration: TimeInterval) {
        guard let screen = NSScreen.main else { return }
        let size = content.frame.size
        let margin: CGFloat = 40
        let origin: NSPoint
        switch anchor {
        case .bottomCenter:
            origin = NSPoint(x: screen.frame.midX - size.width / 2, y: screen.frame.minY + margin)
        case .bottomRight:
            origin = NSPoint(x: screen.frame.maxX - size.width - margin, y: screen.frame.minY + margin)
        }

        let panel = NSPanel(contentRect: NSRect(origin: origin, size: size),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = content
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        huds.append(panel)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.3
                panel.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    panel.orderOut(nil)
                    huds.removeAll { $0 === panel }
                }
            }
        }
    }
}
