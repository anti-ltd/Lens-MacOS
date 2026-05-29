import Foundation

/// A global hotkey: a virtual keycode plus a modifier mask (the raw value of
/// `NSEvent.ModifierFlags`). `keyCode == -1` means "unbound". Codable so the
/// whole per-mode binding table round-trips through UserDefaults as JSON.
public struct HotkeyBinding: Codable, Sendable, Equatable {
    public var keyCode: Int
    public var modifiers: Int

    public init(keyCode: Int = -1, modifiers: Int = 0) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let unbound = HotkeyBinding()

    public var isSet: Bool { keyCode >= 0 }

    /// "⌃⌥⇧⌘A"-style display string. Empty when unbound.
    public var display: String {
        guard isSet else { return "" }
        var s = ""
        // The same bit layout as NSEvent.ModifierFlags.
        if modifiers & (1 << 18) != 0 { s += "⌃" } // control
        if modifiers & (1 << 19) != 0 { s += "⌥" } // option
        if modifiers & (1 << 17) != 0 { s += "⇧" } // shift
        if modifiers & (1 << 20) != 0 { s += "⌘" } // command
        s += Keycodes.label(for: UInt16(keyCode))
        return s
    }
}
