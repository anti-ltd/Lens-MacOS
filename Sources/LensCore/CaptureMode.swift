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
    /// Toggle screen recording (start on first press, stop on the next).
    case video

    public var id: String { rawValue }

    /// Human label for menus and the settings popover.
    public var title: String {
        switch self {
        case .area:        return "Capture Area"
        case .window:      return "Capture Window"
        case .fullScreen:  return "Capture Full Screen"
        case .scrolling:   return "Scrolling Capture"
        case .colorPicker: return "Pick Color"
        case .video:       return "Record Screen"
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
        case .video:       return "Record"
        }
    }

    public var symbol: String {
        switch self {
        case .area:        return "crop"
        case .window:      return "macwindow"
        case .fullScreen:  return "rectangle.inset.filled"
        case .scrolling:   return "arrow.up.arrow.down.square"
        case .colorPicker: return "eyedropper"
        case .video:       return "record.circle"
        }
    }

    /// Whether this mode produces a still image that flows into the editor /
    /// output pipeline. `colorPicker` copies a hex value; `video` records to a
    /// file — neither feeds the still pipeline.
    public var producesImage: Bool { self != .colorPicker && self != .video }
}
