import Foundation

/// The five ways Lens grabs pixels. Each maps to a global hotkey and a menu
/// item; the capture controller switches on it to drive the right flow.
public enum CaptureMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Drag a rectangle. Ratio-locked when the active preset pins one.
    case area
    /// Click a window; capture just that window (with or without shadow).
    case window
    /// The whole display under the pointer.
    case fullScreen
    /// A long window/web page captured by auto-scrolling and stitching.
    case scrolling
    /// Pick a single pixel's colour with a magnifier loupe (no file written).
    case colorPicker

    public var id: String { rawValue }

    /// Human label for menus and the settings popover.
    public var title: String {
        switch self {
        case .area:        return "Capture Area"
        case .window:      return "Capture Window"
        case .fullScreen:  return "Capture Full Screen"
        case .scrolling:   return "Scrolling Capture"
        case .colorPicker: return "Pick Color"
        }
    }

    /// Short label used on chips / compact rows.
    public var shortTitle: String {
        switch self {
        case .area:        return "Area"
        case .window:      return "Window"
        case .fullScreen:  return "Full Screen"
        case .scrolling:   return "Scrolling"
        case .colorPicker: return "Color"
        }
    }

    public var symbol: String {
        switch self {
        case .area:        return "crop"
        case .window:      return "macwindow"
        case .fullScreen:  return "rectangle.inset.filled"
        case .scrolling:   return "arrow.up.arrow.down.square"
        case .colorPicker: return "eyedropper"
        }
    }

    /// Whether this mode produces an image that flows into the editor/output
    /// pipeline. `colorPicker` does not — it copies a hex value and stops.
    public var producesImage: Bool { self != .colorPicker }
}
