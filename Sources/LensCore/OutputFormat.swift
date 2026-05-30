import Foundation
import UniformTypeIdentifiers

/// Image container Lens writes. Matches the formats macOS screenshots support
/// (PNG, JPEG, plus modern WebP/HEIC), so users aren't downgraded vs the OS.
public enum OutputFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case png, jpeg, heic, tiff

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .png:  return "PNG"
        case .jpeg: return "JPEG"
        case .heic: return "HEIC"
        case .tiff: return "TIFF"
        }
    }

    public var fileExtension: String {
        switch self {
        case .png:  return "png"
        case .jpeg: return "jpg"
        case .heic: return "heic"
        case .tiff: return "tiff"
        }
    }

    public var utType: UTType {
        switch self {
        case .png:  return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        }
    }

    /// Whether a lossy quality value applies (JPEG/HEIC only).
    public var isLossy: Bool { self == .jpeg || self == .heic }

    /// Formats that can preserve an alpha channel (for transparent backdrops).
    public var supportsAlpha: Bool { self == .png || self == .tiff }
}

/// Where a finished capture lands.
public enum CaptureDestination: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Open the annotation editor first; the user saves from there.
    case editor
    /// Write straight to the configured folder (the "quick, repeatable" path).
    case file
    /// Copy the image to the pasteboard, no file.
    case clipboard
    /// Pin it to a floating always-on-top window.
    case pin
    /// Collect into the gallery tray for bulk editing / collaging (rapid capture).
    case tray

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .editor:    return "Open in Editor"
        case .file:      return "Save to Folder"
        case .clipboard: return "Copy to Clipboard"
        case .pin:       return "Pin to Screen"
        case .tray:      return "Add to Tray"
        }
    }

    public var symbol: String {
        switch self {
        case .editor:    return "pencil.and.outline"
        case .file:      return "folder"
        case .clipboard: return "doc.on.clipboard"
        case .pin:       return "pin"
        case .tray:      return "square.grid.2x2"
        }
    }
}
