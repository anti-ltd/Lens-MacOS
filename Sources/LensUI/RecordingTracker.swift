import AppKit
import LensCore

/// Captures the event track that rides alongside a raw screen recording — the
/// cursor path (sampled at the recording fps), clicks, and keystrokes — in
/// global top-left points. The Studio render pass consumes the resulting
/// `RecordingEvents`. Cheap by design: just sampling + global monitors.
@MainActor
final class RecordingTracker {
    private var start: Date?
    private var timer: Timer?
    private var monitors: [Any] = []

    private var fps = 60
    private var scale: CGFloat = 2
    private var pixelSize: CGSize = .zero
    private var region: CGRect = .zero

    private var cursors: [RecordingEvents.CursorSample] = []
    private var clicks: [RecordingEvents.ClickSample] = []
    private var keys: [RecordingEvents.KeySample] = []
    private var typingFoci: [RecordingEvents.TypingFocus] = []
    private var lastTypingProbe: Double = -1

    func begin(regionGlobalPoints: CGRect, scale: CGFloat, pixelSize: CGSize, fps: Int) {
        region = regionGlobalPoints
        self.scale = scale
        self.pixelSize = pixelSize
        self.fps = fps
        cursors = []; clicks = []; keys = []; typingFoci = []; lastTypingProbe = -1
        start = Date()

        let interval = 1.0 / Double(max(1, fps))
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleCursor() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        let clickHandler: (NSEvent) -> Void = { [weak self] e in
            MainActor.assumeIsolated { self?.recordClick(e) }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: clickHandler) {
            monitors.append(m)
        }
        let keyHandler: (NSEvent) -> Void = { [weak self] e in
            MainActor.assumeIsolated { self?.recordKey(e) }
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp], handler: keyHandler) {
            monitors.append(m)
        }
    }

    func finish() -> RecordingEvents {
        timer?.invalidate(); timer = nil
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors = []
        let duration = start.map { Date().timeIntervalSince($0) } ?? 0
        return RecordingEvents(
            fps: fps, scale: scale, pixelSize: pixelSize, regionGlobalPoints: region,
            duration: duration, cursors: cursors, clicks: clicks, keys: keys, typingFoci: typingFoci
        )
    }

    // MARK: - Sampling

    private func elapsed() -> Double { start.map { Date().timeIntervalSince($0) } ?? 0 }

    /// `NSEvent.mouseLocation` is global bottom-left; flip to global top-left.
    private func globalTopLeft() -> CGPoint {
        let p = NSEvent.mouseLocation
        let h = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: h - p.y)
    }

    private func sampleCursor() {
        let p = globalTopLeft()
        cursors.append(.init(t: elapsed(), x: Double(p.x), y: Double(p.y)))
    }

    private func recordClick(_ e: NSEvent) {
        let p = globalTopLeft()
        clicks.append(.init(t: elapsed(), x: Double(p.x), y: Double(p.y), button: e.buttonNumber))
    }

    private func recordKey(_ e: NSEvent) {
        let t = elapsed()
        let mods = Int(e.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue)
        keys.append(.init(t: t, keyCode: Int(e.keyCode), modifiers: mods, down: e.type == .keyDown))
        // Sample where typing is happening (caret), throttled — AX queries aren't
        // free, and a few per second is plenty for a smooth zoom target.
        if e.type == .keyDown, t - lastTypingProbe > 0.2 {
            lastTypingProbe = t
            if let p = AccessibilityProbe.typingFocus() {
                typingFoci.append(.init(t: t, x: Double(p.x), y: Double(p.y)))
            }
        }
    }
}
