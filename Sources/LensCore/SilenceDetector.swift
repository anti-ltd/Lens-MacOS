import Foundation
import CoreGraphics

/// Finds the parts of a recording worth keeping — collapsing long idle gaps
/// (no cursor movement, clicks, or keystrokes) down to a short beat. Returns
/// keep-intervals in the *render* timeline (0-based, after trim), which the
/// cutter then stitches together. Pure + testable.
public enum SilenceDetector {

    /// - Parameters:
    ///   - minIdle: only gaps longer than this are trimmed.
    ///   - keepPad: how much of a trimmed gap to leave (a breathing beat).
    /// - Returns: sorted, non-overlapping `(start, end)` seconds in render time.
    public static func keepIntervals(
        events: RecordingEvents,
        trimStart: Double = 0,
        trimEnd: Double? = nil,
        minIdle: Double = 1.2,
        keepPad: Double = 0.4
    ) -> [(start: Double, end: Double)] {
        let fps = max(15, events.fps)
        let dt = 1.0 / Double(fps)
        let start = max(0, trimStart)
        let end = max(start + dt, trimEnd ?? events.duration)
        let n = max(1, Int(((end - start) / dt).rounded(.up)))

        let clickKeyTimes = events.clicks.map(\.t) + events.keys.filter(\.down).map(\.t)
        let speedThresh: CGFloat = 4 // frame px per sample

        // Activity per sample.
        var active = [Bool](repeating: false, count: n)
        var prev: CGPoint?
        for i in 0..<n {
            let t = start + Double(i) * dt
            var moved = false
            if let p = events.cursorPixel(at: t) {
                if let prev { moved = hypot(p.x - prev.x, p.y - prev.y) > speedThresh }
                prev = p
            }
            let nearEvent = clickKeyTimes.contains { abs($0 - t) < 0.3 }
            active[i] = moved || nearEvent
        }

        // Keep: active samples, plus the first `keepPad` of each long idle gap.
        var keep = active
        let pad = max(1, Int((keepPad / dt).rounded()))
        var i = 0
        while i < n {
            if active[i] { i += 1; continue }
            var j = i
            while j < n, !active[j] { j += 1 }
            let runLen = Double(j - i) * dt
            if runLen > minIdle {
                for k in i..<min(j, i + pad) { keep[k] = true } // leave a beat
            } else {
                for k in i..<j { keep[k] = true }               // short gap, keep it all
            }
            i = j
        }

        // Coalesce kept samples into render-time intervals.
        var intervals: [(Double, Double)] = []
        i = 0
        while i < n {
            if !keep[i] { i += 1; continue }
            var j = i
            while j < n, keep[j] { j += 1 }
            let s = Double(i) * dt
            let e = min(Double(j) * dt, end - start)
            if e > s { intervals.append((s, e)) }
            i = j
        }
        if intervals.isEmpty { intervals = [(0, end - start)] }
        return intervals.map { (start: $0.0, end: $0.1) }
    }

    /// Whether cutting would meaningfully shorten the clip (else skip the work).
    public static func worthCutting(_ intervals: [(start: Double, end: Double)], fullDuration: Double) -> Bool {
        let kept = intervals.reduce(0) { $0 + ($1.end - $1.start) }
        return kept < fullDuration - 0.25
    }
}
