import Foundation
import CoreGraphics

/// How a recording (or a still) is framed into a presentation scene: the
/// background behind it, breathing room, rounded corners + shadow, optional
/// window/browser chrome, and the output aspect. Drives `SceneCompositor`.
public struct SceneStyle: Codable, Sendable, Equatable {
    public enum Background: Codable, Sendable, Equatable {
        case transparent
        case solid(RGBAColor)
        case gradient(RGBAColor, RGBAColor)
        case wallpaper(String) // file path
    }

    public enum Chrome: String, Codable, Sendable, CaseIterable, Identifiable {
        case none, window, browser
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .none: return "None"
            case .window: return "Window"
            case .browser: return "Browser"
            }
        }
    }

    public enum Aspect: String, Codable, Sendable, CaseIterable, Identifiable {
        case source, r16_9, r1_1, r9_16, r4_3
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .source: return "Source"
            case .r16_9: return "16:9"
            case .r1_1: return "1:1"
            case .r9_16: return "9:16"
            case .r4_3: return "4:3"
            }
        }
        /// width / height, or nil to keep the framed window's own aspect.
        public var ratio: CGFloat? {
            switch self {
            case .source: return nil
            case .r16_9: return 16.0 / 9.0
            case .r1_1: return 1
            case .r9_16: return 9.0 / 16.0
            case .r4_3: return 4.0 / 3.0
            }
        }
    }

    public var background: Background
    /// Padding as a fraction of the framed window's longest side.
    public var insetFraction: CGFloat
    /// Corner radius (pixels) on the framed window.
    public var cornerRadius: CGFloat
    public var shadowOpacity: Double
    public var shadowBlur: CGFloat
    public var chrome: Chrome
    public var aspect: Aspect
    /// Subtle 3D lean of the window (0 = flat). Narrows the top edge for a
    /// receding-perspective look. Keep small.
    public var tilt: CGFloat

    public init(
        background: Background = .gradient(RGBAColor(hex: "#5B8CFF")!, RGBAColor(hex: "#A855F7")!),
        insetFraction: CGFloat = 0.08,
        cornerRadius: CGFloat = 18,
        shadowOpacity: Double = 0.45,
        shadowBlur: CGFloat = 60,
        chrome: Chrome = .window,
        aspect: Aspect = .source,
        tilt: CGFloat = 0
    ) {
        self.background = background
        self.insetFraction = insetFraction
        self.cornerRadius = cornerRadius
        self.shadowOpacity = shadowOpacity
        self.shadowBlur = shadowBlur
        self.chrome = chrome
        self.aspect = aspect
        self.tilt = tilt
    }

    // Tolerant decode: fields added over time default rather than failing.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        background = try c.decodeIfPresent(Background.self, forKey: .background) ?? .gradient(RGBAColor(hex: "#5B8CFF")!, RGBAColor(hex: "#A855F7")!)
        insetFraction = try c.decodeIfPresent(CGFloat.self, forKey: .insetFraction) ?? 0.08
        cornerRadius = try c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius) ?? 18
        shadowOpacity = try c.decodeIfPresent(Double.self, forKey: .shadowOpacity) ?? 0.45
        shadowBlur = try c.decodeIfPresent(CGFloat.self, forKey: .shadowBlur) ?? 60
        chrome = try c.decodeIfPresent(Chrome.self, forKey: .chrome) ?? .window
        aspect = try c.decodeIfPresent(Aspect.self, forKey: .aspect) ?? .source
        tilt = try c.decodeIfPresent(CGFloat.self, forKey: .tilt) ?? 0
    }
}

/// The ready-made looks offered before the full Studio editor (S7) lands.
public enum StudioPreset: String, CaseIterable, Codable, Sendable, Identifiable {
    case clean, marketing, window, browser, vertical

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .clean: return "Clean"
        case .marketing: return "Marketing"
        case .window: return "Window"
        case .browser: return "Browser"
        case .vertical: return "Vertical"
        }
    }

    public var style: SceneStyle {
        switch self {
        case .clean:
            return SceneStyle(background: .solid(RGBAColor(hex: "#0D1326")!),
                              insetFraction: 0.05, cornerRadius: 14, shadowOpacity: 0.35,
                              shadowBlur: 40, chrome: .none, aspect: .source)
        case .marketing:
            return SceneStyle(background: .gradient(RGBAColor(hex: "#5B8CFF")!, RGBAColor(hex: "#A855F7")!),
                              insetFraction: 0.09, cornerRadius: 18, shadowOpacity: 0.5,
                              shadowBlur: 70, chrome: .window, aspect: .r16_9)
        case .window:
            return SceneStyle(background: .gradient(RGBAColor(hex: "#1B2030")!, RGBAColor(hex: "#0B0E18")!),
                              insetFraction: 0.07, cornerRadius: 16, shadowOpacity: 0.5,
                              shadowBlur: 60, chrome: .window, aspect: .source)
        case .browser:
            return SceneStyle(background: .gradient(RGBAColor(hex: "#2A2140")!, RGBAColor(hex: "#0E0A1C")!),
                              insetFraction: 0.07, cornerRadius: 16, shadowOpacity: 0.5,
                              shadowBlur: 60, chrome: .browser, aspect: .source)
        case .vertical:
            return SceneStyle(background: .gradient(RGBAColor(hex: "#5B8CFF")!, RGBAColor(hex: "#A855F7")!),
                              insetFraction: 0.1, cornerRadius: 20, shadowOpacity: 0.5,
                              shadowBlur: 70, chrome: .window, aspect: .r9_16)
        }
    }
}
