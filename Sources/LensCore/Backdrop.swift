import Foundation
import CoreGraphics

/// An RGBA colour that's Codable and free of an AppKit dependency, so the model
/// layer stays UI-agnostic. Components are 0...1.
public struct RGBAColor: Codable, Sendable, Equatable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let clear = RGBAColor(r: 0, g: 0, b: 0, a: 0)
    public static let white = RGBAColor(r: 1, g: 1, b: 1)
    public static let black = RGBAColor(r: 0, g: 0, b: 0)

    /// Parse "#RRGGBB" / "#RRGGBBAA" (and the no-# forms). Returns nil on garbage.
    public init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let v = UInt64(s, radix: 16) else { return nil }
        switch s.count {
        case 6:
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        case 8:
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        default:
            return nil
        }
    }

    public var hex: String {
        String(format: "#%02X%02X%02X",
               Int((r * 255).rounded()), Int((g * 255).rounded()), Int((b * 255).rounded()))
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: r, green: g, blue: b, alpha: a)
    }
}

/// The styling applied around a captured image to make it presentation-ready:
/// a background fill, breathing-room padding, rounded corners, and a drop
/// shadow. Transparent background + zero padding is a clean cut-out.
public struct Backdrop: Codable, Sendable, Equatable {
    public enum Fill: Codable, Sendable, Equatable {
        case transparent
        case solid(RGBAColor)
        /// Linear gradient from `from` (top-leading) to `to` (bottom-trailing).
        case gradient(from: RGBAColor, to: RGBAColor)
    }

    public var fill: Fill
    /// Uniform padding (in points) between the image and the backdrop edge.
    public var padding: CGFloat
    /// Corner radius applied to the captured image (rounded rect mask).
    public var cornerRadius: CGFloat
    /// Drop-shadow opacity (0 = no shadow) and blur radius.
    public var shadowOpacity: Double
    public var shadowBlur: CGFloat

    public init(
        fill: Fill = .transparent,
        padding: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        shadowOpacity: Double = 0,
        shadowBlur: CGFloat = 30
    ) {
        self.fill = fill
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.shadowOpacity = shadowOpacity
        self.shadowBlur = shadowBlur
    }

    /// No-op backdrop: image passes through untouched.
    public static let none = Backdrop()

    /// A flattering default for marketing shots — soft violet gradient, generous
    /// padding, rounded corners, a gentle shadow.
    public static let marketing = Backdrop(
        fill: .gradient(
            from: RGBAColor(hex: "#5B8CFF")!,
            to: RGBAColor(hex: "#A855F7")!
        ),
        padding: 64,
        cornerRadius: 14,
        shadowOpacity: 0.35,
        shadowBlur: 40
    )

    /// Clean cut-out for README embedding — transparent, rounded, soft shadow.
    public static let clean = Backdrop(
        fill: .transparent,
        padding: 40,
        cornerRadius: 12,
        shadowOpacity: 0.25,
        shadowBlur: 24
    )

    /// Whether this backdrop changes the image at all (used to skip compositing).
    public var isIdentity: Bool {
        if case .transparent = fill, padding == 0, cornerRadius == 0, shadowOpacity == 0 {
            return true
        }
        return false
    }
}
