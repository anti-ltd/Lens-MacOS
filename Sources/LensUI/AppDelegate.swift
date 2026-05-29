import AppKit
import SwiftUI
import iUX_MacOS
import LensCore

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    // iUX-MacOS owns the status item, the right-click settings popover, and the
    // left-click capture menu. One instance lives for the process lifetime; the
    // menu is rebuilt on every click so hotkey hints stay current.
    private var menuBar: MenuBarController?
    private var instanceLockFD: Int32 = -1

    public override init() { super.init() }

    // Lens is LSUIElement — the menu-bar item is the whole app. The pop-out
    // settings window and editor windows are transient; closing one must not
    // terminate the process.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationWillFinishLaunching(_ notification: Notification) {
        // appstage capture builds skip the single-instance lock so they can run
        // alongside a real Lens. Compiled out of normal/release builds.
        #if APPSTAGE
        if AppStageCapture.state != nil { return }
        #endif
        guard acquireInstanceLock() else {
            activateExistingInstance()
            exit(0)
        }
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // appstage screenshot mode: render one UI state on-screen and wait to be
        // captured. Skips the status item and live services. Capture builds only.
        #if APPSTAGE
        if let state = AppStageCapture.state {
            AppStageCapture.run(state: state)
            return
        }
        #endif

        setupMenuBar()
        GlobalShortcutManager.shared.start()
        suppressAutoOpenedWindows()

        // The global capture hotkeys can only receive key events once Lens is
        // Accessibility-trusted. Prompt on launch when it isn't — the system
        // shows its dialog only once per identity, so this guides first-run
        // setup without nagging. Granting re-arms the monitor.
        if !CaptureController.hasAccessibilityPermission() {
            CaptureController.requestAccessibilityPermission()
        }
    }

    // MARK: - Menu bar

    private func setupMenuBar() {
        // Left-click is the everyday capture menu; settings sit one right-click
        // away. `activatesOnShow` keeps the popover's text fields (filename
        // template, preset name) focusable from an accessory app.
        menuBar = MenuBarController(
            symbolName: "camera.viewfinder",
            accessibilityLabel: "Lens",
            popoverSize: NSSize(width: 360, height: 480),
            rootView: SettingsPopoverView(),
            clickStyle: .leftClickMenu,
            activatesOnShow: true,
            menuProvider: { [weak self] in self?.buildMainMenu() }
        )
    }

    private func buildMainMenu() -> NSMenu {
        let menu = NSMenu()
        for mode in CaptureMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(captureFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: mode.symbol, accessibilityDescription: nil)
            item.representedObject = mode.rawValue
            if let (key, mods) = menuShortcut(for: mode) {
                item.keyEquivalent = key
                item.keyEquivalentModifierMask = mods
            }
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: nil)
        menu.addItem(quit)
        return menu
    }

    /// Reflect the configured hotkey as the menu item's key-equivalent, when it
    /// has a plain key-equivalent representation.
    private func menuShortcut(for mode: CaptureMode) -> (String, NSEvent.ModifierFlags)? {
        let b = LensSettings.shared.binding(for: mode)
        guard b.isSet, let key = Keycodes.keyEquivalent(for: UInt16(b.keyCode)) else { return nil }
        let mods = NSEvent.ModifierFlags(rawValue: UInt(b.modifiers)).intersection(.deviceIndependentFlagsMask)
        return (key, mods)
    }

    @objc private func captureFromMenu(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CaptureMode(rawValue: raw) else { return }
        CaptureController.shared.perform(mode)
    }

    @objc private func showSettings() { SettingsWindowOpener.open() }

    // MARK: - Window suppression

    // SwiftUI's `Window(id:)` scene auto-opens at launch. Lens is LSUIElement —
    // the settings window opens on demand. Close just that window if SwiftUI
    // brought it up, matched by identifier; a blanket close would also kill the
    // status item's backing window.
    private func suppressAutoOpenedWindows() {
        let targetID = SettingsPopoverView.windowID
        DispatchQueue.main.async {
            for window in NSApp.windows {
                guard let id = window.identifier?.rawValue, id.contains(targetID) else { continue }
                window.close()
            }
        }
    }

    // MARK: - Single instance

    private func acquireInstanceLock() -> Bool {
        let id = Bundle.main.bundleIdentifier ?? "ltd.anti.lens"
        let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("\(id).lock")
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }
        if flock(fd, LOCK_EX | LOCK_NB) != 0 {
            close(fd)
            return false
        }
        instanceLockFD = fd
        return true
    }

    private func activateExistingInstance() {
        guard let id = Bundle.main.bundleIdentifier else { return }
        let me = NSRunningApplication.current
        NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first { $0.processIdentifier != me.processIdentifier }?
            .activate()
    }
}
