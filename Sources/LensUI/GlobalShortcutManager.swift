import AppKit
import Combine
import LensCore

/// Watches the global keyboard for every configured capture hotkey and fires the
/// matching `CaptureMode`. One monitor covers all modes; it re-arms whenever the
/// binding table changes. Mirrors FileMaster's manager, widened to a table.
@MainActor
final class GlobalShortcutManager {
    static let shared = GlobalShortcutManager()

    private var monitor: Any?
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        LensSettings.shared.$hotkeys
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateMonitor() }
            .store(in: &cancellables)
        updateMonitor()
    }

    /// (Re)arm the global key monitor. Internal so granting Accessibility can
    /// re-arm it immediately — `addGlobalMonitorForEvents` returns a live monitor
    /// even without the grant, but it never receives key events until the process
    /// is Accessibility-trusted, so we re-create it once permission lands.
    func updateMonitor() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        // Only a global monitor — it fires while *other* apps are frontmost,
        // which is exactly when a menu-bar capture tool is used. No local
        // monitor, so our own popover keystrokes are never swallowed.
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { Self.handle(event) }
        }
    }

    private static func handle(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        for mode in CaptureMode.allCases {
            let b = LensSettings.shared.binding(for: mode)
            guard b.isSet, event.keyCode == UInt16(b.keyCode) else { continue }
            let want = NSEvent.ModifierFlags(rawValue: UInt(b.modifiers))
                .intersection(.deviceIndependentFlagsMask)
            guard mods == want else { continue }
            CaptureController.shared.perform(mode)
            return
        }
    }
}
