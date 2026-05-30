import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LensCore

/// Opens standalone Studio project windows (new or from a `.lensproj`).
@available(macOS 14.0, *)
@MainActor
enum StudioProjectWindowController {
    private static var windows: [ProjectWindow] = []

    static func newProject() {
        present(StudioProjectModel())
    }

    static func openWithPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes = [UTType(filenameExtension: StudioProject.fileExtension) ?? .json]
        panel.message = "Choose a Lens project"
        guard panel.runModal() == .OK, let url = panel.url, let project = StudioProject.load(from: url) else { return }
        present(StudioProjectModel(project: project, url: url))
    }

    private static func present(_ model: StudioProjectModel) {
        NSApp.setActivationPolicy(.regular)
        let w = ProjectWindow(model: model)
        windows.append(w)
        w.show()
    }

    fileprivate static func remove(_ w: ProjectWindow) {
        windows.removeAll { $0 === w }
        let others = NSApp.windows.contains { $0.isVisible && $0.title.hasPrefix("Lens —") }
        if !others { NSApp.setActivationPolicy(.accessory) }
    }
}

@available(macOS 14.0, *)
@MainActor
private final class ProjectWindow: NSObject, NSWindowDelegate {
    private let model: StudioProjectModel
    private var window: NSWindow?

    init(model: StudioProjectModel) { self.model = model; super.init() }

    func show() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false)
        win.title = "Lens — Project"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.contentView = NSHostingView(rootView: StudioProjectView(model: model))
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        StudioProjectWindowController.remove(self)
    }
}
