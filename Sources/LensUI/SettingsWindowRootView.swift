import SwiftUI
import AppKit
import iUX_MacOS
import LensCore

/// The window companion to the popover — a sidebar of the same tabs, same
/// per-tab content. Lives inside the SwiftUI `Window` scene declared in
/// `LensApp`; promoted to `.regular` activation while visible so the otherwise-
/// accessory app can accept clicks and surface in Cmd-Tab. Mirrors FileMaster.
public struct SettingsWindowRootView: View {
    // Selection lives here, not inside iUX's `SettingsWindow` — the generic
    // wrapper can't host the `@State` without `NavigationSplitView` dropping
    // sidebar clicks (rows render, but selection never updates).
    @State private var selection: LensTab? = .capture

    public init() {}

    public var body: some View {
        SettingsWindow(title: "Lens", selection: $selection) { tab in
            LensTabContent(tab: tab)
        }
        .onAppear { NSApp.setActivationPolicy(.regular) }
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        // Capture SwiftUI's `OpenWindowAction` so AppKit code (the menu-bar
        // "Settings" item) can open this window.
        .background(SettingsWindowOpenerBridge())
    }
}

/// Bridges SwiftUI's `@Environment(\.openWindow)` to AppKit. AppKit menu
/// actions can't reach the SwiftUI environment, so we stash the action into a
/// `@MainActor` static at render time and call it from the AppDelegate.
@MainActor
public enum SettingsWindowOpener {
    public static var action: OpenWindowAction?

    public static func open() {
        guard let action else { NSSound.beep(); return }
        action(id: SettingsPopoverView.windowID)
        NSApp.activate(ignoringOtherApps: true)
        let id = SettingsPopoverView.windowID
        DispatchQueue.main.async {
            for window in NSApp.windows {
                guard let raw = window.identifier?.rawValue, raw.contains(id) else { continue }
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }
}

private struct SettingsWindowOpenerBridge: View {
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { SettingsWindowOpener.action = openWindow }
    }
}
