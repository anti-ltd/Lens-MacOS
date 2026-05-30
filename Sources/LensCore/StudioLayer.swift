import Foundation
import CoreGraphics

/// An overlay placed on the Studio timeline — a text/title or an image/sticker
/// shown for a time range at a position over the video. The render composites
/// active layers on top of everything (fixed, not zoomed).
public struct StudioLayer: Codable, Sendable, Identifiable, Equatable {
    public enum Kind: Codable, Sendable, Equatable {
        case text(String)
        case image(String) // file path
    }

    public var id: UUID
    public var kind: Kind
    /// When it appears (seconds, render time) and for how long. `duration <= 0`
    /// means "the whole clip".
    public var start: Double
    public var duration: Double
    /// Centre position, normalized 0…1 with the origin at the top-left.
    public var x: Double
    public var y: Double
    /// Height as a fraction of the canvas height (text uses it as font size).
    public var scale: Double
    public var opacity: Double
    public var color: RGBAColor
    /// Fade in/out durations (seconds). 0 = appear/disappear instantly.
    public var fadeIn: Double
    public var fadeOut: Double
    /// Optional end position — when set, the layer moves there over its duration.
    public var endX: Double?
    public var endY: Double?

    public init(
        id: UUID = UUID(), kind: Kind, start: Double = 0, duration: Double = 0,
        x: Double = 0.5, y: Double = 0.5, scale: Double = 0.12, opacity: Double = 1,
        color: RGBAColor = .white, fadeIn: Double = 0.3, fadeOut: Double = 0.3,
        endX: Double? = nil, endY: Double? = nil
    ) {
        self.id = id
        self.kind = kind
        self.start = start
        self.duration = duration
        self.x = x
        self.y = y
        self.scale = scale
        self.opacity = opacity
        self.color = color
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.endX = endX
        self.endY = endY
    }

    /// Opacity multiplier from the fade envelope at time `t` (0…1).
    public func fadeFactor(at t: Double) -> Double {
        var f = 1.0
        if fadeIn > 0, t - start < fadeIn { f = (t - start) / fadeIn }
        if duration > 0, fadeOut > 0 {
            let end = start + duration
            if end - t < fadeOut { f = min(f, (end - t) / fadeOut) }
        }
        return max(0, min(1, f))
    }

    /// Position at time `t` (normalized), interpolating toward the end point.
    public func position(at t: Double) -> (x: Double, y: Double) {
        guard duration > 0, endX != nil || endY != nil else { return (x, y) }
        let p = min(1, max(0, (t - start) / duration))
        return (x + ((endX ?? x) - x) * p, y + ((endY ?? y) - y) * p)
    }

    public func isActive(at t: Double) -> Bool {
        guard t >= start else { return false }
        return duration <= 0 || t <= start + duration
    }

    public var isText: Bool { if case .text = kind { return true }; return false }

    public var summary: String {
        switch kind {
        case let .text(s): return s.isEmpty ? "Text" : s
        case let .image(p): return URL(fileURLWithPath: p).lastPathComponent
        }
    }
}
