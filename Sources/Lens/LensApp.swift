import SwiftUI
import AppKit
import LensUI

// Lens — a precise, repeatable screenshot utility for macOS.
//
//   • MenuBarController — iUX-MacOS's menu bar host. Left-click opens the
//                         capture menu; right-click opens the settings popover
//                         with its pop-out button.
//   • CaptureController — orchestrates each capture mode end to end.
//
// Dev tool: `--icon <dir>` renders the AppIcon.iconset folder, then exits.
@main
struct LensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        // Render the icon synchronously before SwiftUI's lifecycle starts, so
        // `make icon` stays fast and headless. Matches FileMaster's pattern.
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--icon"), idx + 1 < args.count {
            AppIconRenderer.run(directory: args[idx + 1])
            exit(0)
        }
    }

    var body: some Scene {
        // The pop-out settings window. A SwiftUI `Window` scene (not a hand-
        // built NSWindow) gives `NavigationSplitView` the unified toolbar,
        // transparent titlebar, and vibrant sidebar. Opened on demand.
        Window("Lens", id: SettingsPopoverView.windowID) {
            SettingsWindowRootView()
        }
        .defaultSize(width: 720, height: 540)
        .windowToolbarStyle(.unified)

        Settings { EmptyView() }
    }
}
