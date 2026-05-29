import AppKit
import SwiftUI
import LensCore

/// Opens an annotation editor window for a capture and keeps it alive until the
/// user closes it. Lens is LSUIElement, so we promote to `.regular` while an
/// editor is up (Dock tile + Cmd-Tab), dropping back when the last one closes.
@MainActor
enum EditorWindowController {
    private static var controllers: [Editor] = []

    static func present(capture: CaptureController.Capture) {
        let model = EditorModel(base: capture.image, preset: capture.preset)
        let editor = Editor(model: model)
        controllers.append(editor)
        NSApp.setActivationPolicy(.regular)
        editor.show()
    }

    fileprivate static func remove(_ editor: Editor) {
        controllers.removeAll { $0 === editor }
        if controllers.isEmpty {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// One editor window + its hosting view. An `NSWindowController` so it owns the
/// window's lifetime and we can react to close.
private final class Editor: NSObject, NSWindowDelegate {
    private let model: EditorModel
    private var window: NSWindow?

    init(model: EditorModel) {
        self.model = model
        super.init()
    }

    func show() {
        // Size the window to a comfortable fraction of the screen, capped to the
        // capture's own size so small grabs don't open huge windows.
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let maxW = screen.width * 0.8, maxH = screen.height * 0.8
        let iw = CGFloat(model.base.width), ih = CGFloat(model.base.height)
        let scale = min(maxW / iw, maxH / ih, 1)
        let content = NSSize(width: max(iw * scale, 700), height: max(ih * scale + 96, 520))

        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: content),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.title = "Lens — Editor"
        win.titlebarAppearsTransparent = false
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()

        let root = EditorView(model: model, onClose: { [weak self] in self?.window?.close() })
        win.contentView = NSHostingView(rootView: root)
        window = win

        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        EditorWindowController.remove(self)
    }
}
