import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LensCore

/// Opens the Studio editor for a recording session folder.
@available(macOS 14.0, *)
@MainActor
enum StudioEditorWindowController {
    private static var editors: [Editor] = []

    /// Prompt for a session folder (or its screen.mp4) and open the editor.
    static func openWithPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a recording session folder (or its screen.mp4)"
        panel.directoryURL = URL(fileURLWithPath: (LensSettings.shared.saveFolderPath as NSString).expandingTildeInPath)
            .appendingPathComponent("Lens Recordings", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let folder = url.hasDirectoryPath ? url : url.deletingLastPathComponent()
        open(folder: folder)
    }

    static func open(folder: URL) {
        NSApp.setActivationPolicy(.regular)
        let editor = Editor(folder: folder)
        editors.append(editor)
        editor.show()
    }

    fileprivate static func remove(_ editor: Editor) {
        editors.removeAll { $0 === editor }
        let others = NSApp.windows.contains { $0.isVisible && $0.title.hasPrefix("Lens —") }
        if !others { NSApp.setActivationPolicy(.accessory) }
    }
}

@available(macOS 14.0, *)
@MainActor
private final class Editor: NSObject, NSWindowDelegate {
    private let model: StudioEditorModel
    private var window: NSWindow?

    init(folder: URL) {
        self.model = StudioEditorModel(folder: folder)
        super.init()
    }

    func show() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        win.title = "Lens — Studio"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.contentView = NSHostingView(rootView: StudioEditorView(model: model))
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        StudioEditorWindowController.remove(self)
    }
}
