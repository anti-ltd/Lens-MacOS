import AppKit
import SwiftUI

/// Opens (and reuses) the gallery window that manages the rapid-capture tray.
@MainActor
enum GalleryWindowController {
    private static var controller: Gallery?

    static func open() {
        NSApp.setActivationPolicy(.regular)
        if let c = controller {
            c.bringToFront()
            return
        }
        let c = Gallery()
        controller = c
        c.show()
    }

    fileprivate static func remove(_ gallery: Gallery) {
        controller = nil
        // Drop the Dock tile only if no editor windows are still up.
        let hasOtherWindows = NSApp.windows.contains { $0.isVisible && $0.title.hasPrefix("Lens —") }
        if !hasOtherWindows { NSApp.setActivationPolicy(.accessory) }
    }
}

private final class Gallery: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered, defer: false
        )
        win.title = "Lens — Gallery"
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.center()
        win.contentView = NSHostingView(rootView: GalleryView())
        window = win
        NSApp.activate(ignoringOtherApps: true)
        win.makeKeyAndOrderFront(nil)
    }

    func bringToFront() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        GalleryWindowController.remove(self)
    }
}
