import Foundation

/// Virtual-keycode ↔ label maps, shared by the shortcut recorder, the global
/// hotkey monitor, and the menu builder so the three never drift. Lifted from
/// FileMaster's recorder; kept in Core so any layer can render a binding.
public enum Keycodes {
    /// Display label for a keycode ("A", "Space", "→", "F1"). Falls back to a
    /// bracketed raw code for anything unmapped.
    public static func label(for keyCode: UInt16) -> String {
        map[keyCode] ?? "[\(keyCode)]"
    }

    public static let map: [UInt16: String] = [
        0: "A",  1: "S",  2: "D",  3: "F",  4: "H",  5: "G",  6: "Z",  7: "X",
        8: "C",  9: "V",  11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
        16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "⇥",
        49: "Space", 50: "`", 51: "⌫",
        65: ".", 67: "*", 69: "+", 75: "/", 76: "↩", 78: "-", 81: "=",
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5",
        88: "6", 89: "7", 91: "8", 92: "9",
        96: "F5", 97: "F6", 98: "F7",  99: "F3", 100: "F8",
        101: "F9", 103: "F11", 109: "F10", 111: "F12",
        118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    /// Lowercase character for an `NSMenuItem.keyEquivalent`, or nil for keys
    /// with no plain key-equivalent. Function/arrow keys map to their unicode.
    public static func keyEquivalent(for keyCode: UInt16) -> String? {
        equivalentMap[keyCode]
    }

    private static let equivalentMap: [UInt16: String] = [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x",
        8: "c", 9: "v", 11: "b", 12: "q", 13: "w", 14: "e", 15: "r",
        16: "y", 17: "t", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
        23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
        30: "]", 31: "o", 32: "u", 33: "[", 34: "i", 35: "p",
        37: "l", 38: "j", 39: "'", 40: "k", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "n", 46: "m", 47: ".", 49: " ", 50: "`",
    ]
}
