import AppKit
import CoreImage
import CoreGraphics

/// Cursor-cinema tuning. Lens draws its *own* cursor from the event track (so it
/// can be enlarged, smoothed, and faded when idle) plus click ripples and an
/// optional spotlight. For a clean result, record with the system cursor off so
/// only this cinematic cursor shows.
public struct CursorStyle: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Cursor size multiplier (1 ≈ a slightly-enlarged pointer).
    public var size: CGFloat
    /// Position smoothing time-constant (seconds).
    public var smoothing: Double
    public var clickRipples: Bool
    public var rippleColor: RGBAColor
    /// Dim everything outside a radius around the cursor (0 = off).
    public var spotlight: Double
    public var hideWhenIdle: Bool

    public init(
        enabled: Bool = false, size: CGFloat = 1.5, smoothing: Double = 0.12,
        clickRipples: Bool = true, rippleColor: RGBAColor = RGBAColor(hex: "#FFFFFF")!,
        spotlight: Double = 0, hideWhenIdle: Bool = true
    ) {
        self.enabled = enabled
        self.size = size
        self.smoothing = smoothing
        self.clickRipples = clickRipples
        self.rippleColor = rippleColor
        self.spotlight = spotlight
        self.hideWhenIdle = hideWhenIdle
    }
}

/// Precomputes the smoothed cursor path (in CI canvas coords, pre-zoom), an
/// idle-fade alpha timeline, and the click moments. Read at render time and
/// projected through the camera so the cursor sits correctly over the zoomed
/// scene at a constant on-screen size.
@available(macOS 14.0, *)
final class CursorPlan {
    let clicks: [(t: Double, point: CGPoint)] // canvas pre-zoom
    private let dt: Double
    private let xs: [CGFloat]
    private let ys: [CGFloat]
    private let alphas: [CGFloat]

    init(events: RecordingEvents, screenRectCI: CGRect, canvasSize: CGSize, style: CursorStyle) {
        let fps = max(15, events.fps)
        let dt = 1.0 / Double(fps); self.dt = dt
        let n = max(1, Int((events.duration / dt).rounded(.up)) + 1)

        func canvas(at t: Double) -> CGPoint {
            guard let fp = events.cursorPixel(at: t) else {
                return CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            }
            return CGPoint(x: screenRectCI.minX + fp.x, y: screenRectCI.maxY - fp.y)
        }

        var px = [CGFloat](repeating: 0, count: n)
        var py = [CGFloat](repeating: 0, count: n)
        for i in 0..<n { let p = canvas(at: Double(i) * dt); px[i] = p.x; py[i] = p.y }

        // Idle fade: active near movement or clicks.
        let clickTimes = events.clicks.map(\.t)
        var a = [CGFloat](repeating: 1, count: n)
        if style.hideWhenIdle {
            let speedThresh: CGFloat = 3 // canvas px per frame-sample — hide only when truly parked
            for i in 0..<n {
                let t = Double(i) * dt
                let moved = i > 0 ? hypot(px[i] - px[i-1], py[i] - py[i-1]) : 0
                let nearClick = clickTimes.contains { abs($0 - t) < 0.8 }
                a[i] = (moved > speedThresh || nearClick) ? 1 : 0
            }
        }

        let alpha = CGFloat(dt / (style.smoothing + dt))
        self.xs = Self.smooth(px, alpha: alpha)
        self.ys = Self.smooth(py, alpha: alpha)
        self.alphas = Self.smooth(a, alpha: CGFloat(dt / (0.25 + dt)))
        self.clicks = events.clicks.map { ($0.t, canvas(at: $0.t)) }
    }

    private static func smooth(_ x: [CGFloat], alpha: CGFloat) -> [CGFloat] {
        guard x.count > 1 else { return x }
        var y = x
        for i in 1..<y.count { y[i] = y[i-1] + alpha * (y[i] - y[i-1]) }
        for i in stride(from: y.count - 2, through: 0, by: -1) { y[i] = y[i+1] + alpha * (y[i] - y[i+1]) }
        return y
    }

    func position(at t: Double) -> CGPoint {
        guard !xs.isEmpty else { return .zero }
        let p = max(0, t / dt); let i = Int(p)
        if i >= xs.count - 1 { return CGPoint(x: xs[xs.count-1], y: ys[ys.count-1]) }
        let f = CGFloat(p - Double(i))
        return CGPoint(x: xs[i] + (xs[i+1]-xs[i])*f, y: ys[i] + (ys[i+1]-ys[i])*f)
    }

    func alpha(at t: Double) -> CGFloat {
        guard !alphas.isEmpty else { return 1 }
        let p = max(0, t / dt); let i = min(alphas.count - 1, Int(p))
        return alphas[i]
    }
}

/// Builds the static cursor + ripple-ring images once.
@available(macOS 14.0, *)
enum CursorArt {
    /// A classic black pointer with a white outline, tip at the image's top-left.
    static func pointer(sizePx: CGFloat) -> CIImage? {
        let s = max(8, sizePx)
        guard let cg = draw(width: Int(s), height: Int(s), { _ in
            let p = NSBezierPath()
            // Unit pointer (top-left origin), tip at (0,0).
            let pts: [(CGFloat, CGFloat)] = [
                (0, 0), (0, 0.76), (0.20, 0.59), (0.31, 0.88),
                (0.43, 0.83), (0.32, 0.55), (0.55, 0.55),
            ]
            p.move(to: NSPoint(x: pts[0].0 * s, y: pts[0].1 * s))
            for pt in pts.dropFirst() { p.line(to: NSPoint(x: pt.0 * s, y: pt.1 * s)) }
            p.close()
            NSColor.white.setStroke(); p.lineWidth = s * 0.08; p.lineJoinStyle = .round; p.stroke()
            NSColor.black.setFill(); p.fill()
            NSColor.white.setStroke(); p.lineWidth = s * 0.04; p.stroke()
        }) else { return nil }
        return CIImage(cgImage: cg)
    }

    /// A stroked ring (transparent centre) for click ripples; radius ≈ 0.45·size.
    static func ring(sizePx: CGFloat, color: RGBAColor) -> CIImage? {
        let s = max(16, sizePx)
        guard let cg = draw(width: Int(s), height: Int(s), { _ in
            color.nsColor.setStroke()
            let r = NSBezierPath(ovalIn: NSRect(x: s*0.08, y: s*0.08, width: s*0.84, height: s*0.84))
            r.lineWidth = s * 0.04
            r.stroke()
        }) else { return nil }
        return CIImage(cgImage: cg)
    }

    private static func draw(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ns
        ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
        body(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }
}
