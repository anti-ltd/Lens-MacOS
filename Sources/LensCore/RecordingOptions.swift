import Foundation

/// What a screen recording captures. Mirrors the still-capture geometries minus
/// the ones that don't make sense for video.
public enum RecordingSource: String, CaseIterable, Codable, Sendable, Identifiable {
    case fullScreen
    case region
    case window

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fullScreen: return "Full Screen"
        case .region:     return "Region"
        case .window:     return "Window"
        }
    }

    public var symbol: String {
        switch self {
        case .fullScreen: return "rectangle.inset.filled"
        case .region:     return "crop"
        case .window:     return "macwindow"
        }
    }
}

/// Video codec for recordings and Studio renders.
public enum VideoCodec: String, CaseIterable, Codable, Sendable, Identifiable {
    case h264, hevc
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .h264: return "H.264"
        case .hevc: return "HEVC"
        }
    }
}

/// Selectable frame rates for recording.
public enum RecordingFPS: Int, CaseIterable, Codable, Sendable, Identifiable {
    case fps15 = 15, fps24 = 24, fps30 = 30, fps60 = 60
    public var id: Int { rawValue }
    public var label: String { "\(rawValue)" }
}

