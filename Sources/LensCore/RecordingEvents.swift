import Foundation
import CoreGraphics

/// The event track captured alongside a raw screen recording. The Studio render
/// pass reads this to drive the auto-zoom camera, cursor effects, and keystroke
/// overlay — so recording stays cheap (just sampling) and all the cinematic work
/// happens offline against this timeline.
///
/// Positions are stored in **global top-left points**; `framePixel(global:)`
/// maps them into the recorded frame's pixel space using the region + scale.
public struct RecordingEvents: Codable, Sendable {
    public var fps: Int
    public var scale: CGFloat
    /// Recorded frame size, in pixels.
    public var pixelSize: CGSize
    /// The captured area in global top-left points (display frame, dragged
    /// region, or the window's frame at record time).
    public var regionGlobalPoints: CGRect
    public var duration: Double

    public var cursors: [CursorSample]
    public var clicks: [ClickSample]
    public var keys: [KeySample]
    /// Where typing was happening (caret / focused field centre), in global
    /// top-left points — drives typing-aware zoom. Optional for back-compat.
    public var typingFoci: [TypingFocus]

    public init(
        fps: Int, scale: CGFloat, pixelSize: CGSize, regionGlobalPoints: CGRect,
        duration: Double, cursors: [CursorSample] = [], clicks: [ClickSample] = [],
        keys: [KeySample] = [], typingFoci: [TypingFocus] = []
    ) {
        self.fps = fps
        self.scale = scale
        self.pixelSize = pixelSize
        self.regionGlobalPoints = regionGlobalPoints
        self.duration = duration
        self.cursors = cursors
        self.clicks = clicks
        self.keys = keys
        self.typingFoci = typingFoci
    }

    /// Global top-left point → recorded-frame pixel (top-left origin), clamped
    /// to the frame.
    public func framePixel(global p: CGPoint) -> CGPoint {
        let x = (p.x - regionGlobalPoints.minX) * scale
        let y = (p.y - regionGlobalPoints.minY) * scale
        return CGPoint(x: min(max(x, 0), pixelSize.width),
                       y: min(max(y, 0), pixelSize.height))
    }

    /// Linearly-interpolated cursor position (frame pixels) at time `t`.
    public func cursorPixel(at t: Double) -> CGPoint? {
        guard !cursors.isEmpty else { return nil }
        if t <= cursors.first!.t { return framePixel(global: cursors.first!.point) }
        if t >= cursors.last!.t { return framePixel(global: cursors.last!.point) }
        // Samples are time-ordered; find the bracketing pair.
        var lo = 0, hi = cursors.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if cursors[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = cursors[lo], b = cursors[hi]
        let span = b.t - a.t
        let f = span > 0 ? (t - a.t) / span : 0
        let g = CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
        return framePixel(global: g)
    }

    public struct CursorSample: Codable, Sendable {
        public var t: Double, x: Double, y: Double
        public init(t: Double, x: Double, y: Double) { self.t = t; self.x = x; self.y = y }
        public var point: CGPoint { CGPoint(x: x, y: y) }
    }

    public struct ClickSample: Codable, Sendable {
        public var t: Double, x: Double, y: Double, button: Int
        public init(t: Double, x: Double, y: Double, button: Int) { self.t = t; self.x = x; self.y = y; self.button = button }
        public var point: CGPoint { CGPoint(x: x, y: y) }
    }

    public struct KeySample: Codable, Sendable {
        public var t: Double, keyCode: Int, modifiers: Int, down: Bool
        public init(t: Double, keyCode: Int, modifiers: Int, down: Bool) {
            self.t = t; self.keyCode = keyCode; self.modifiers = modifiers; self.down = down
        }
    }

    public struct TypingFocus: Codable, Sendable {
        public var t: Double, x: Double, y: Double
        public init(t: Double, x: Double, y: Double) { self.t = t; self.x = x; self.y = y }
        public var point: CGPoint { CGPoint(x: x, y: y) }
    }

    /// The typing focus nearest `t` within `window`, in global top-left points.
    public func typingFocus(at t: Double, window: Double = 0.5) -> CGPoint? {
        var best: TypingFocus?
        var bestDist = window
        for f in typingFoci {
            let d = abs(f.t - t)
            if d < bestDist { bestDist = d; best = f }
        }
        return best?.point
    }
}
