import AppKit
import CoreImage
import CoreGraphics

/// Frames a recording (or a still) into a presentation scene per a `SceneStyle`:
/// a background, an inset rounded "window" (optionally with macOS/browser
/// chrome) with a drop shadow. Built once per render — all static layers
/// (background, chrome bar, corner mask, shadow) are precomputed, so the
/// per-frame `transform` only scales/places the live frame and composites.
///
/// The same compositor frames still images (Track C) via `frameStill`.
@available(macOS 14.0, *)
public final class SceneCompositor {
    public let canvasSize: CGSize

    private let ci = CIContext()
    private let sourceSize: CGSize
    /// Where the live frame is placed, in CI (bottom-left) canvas coords. Used by
    /// the auto-zoom camera to map cursor positions into canvas space.
    let screenRectCI: CGRect
    private let background: CIImage
    private let chromeBar: CIImage?       // full-canvas, clear except the bar
    private let windowMask: CIImage       // full-canvas rounded-rect alpha mask
    private let baseLayer: CIImage        // shadow composited over background
    private let tilt: CGFloat

    public init(style: SceneStyle, sourcePixelSize: CGSize) {
        let srcW = max(2, sourcePixelSize.width.rounded())
        let srcH = max(2, sourcePixelSize.height.rounded())
        self.sourceSize = CGSize(width: srcW, height: srcH)

        // Chrome bar height scales with content width.
        let barPx: CGFloat
        switch style.chrome {
        case .none: barPx = 0
        case .window: barPx = (srcW * 0.045).rounded()
        case .browser: barPx = (srcW * 0.075).rounded()
        }
        let windowW = srcW
        let windowH = srcH + barPx
        let pad = (style.insetFraction * max(windowW, windowH)).rounded()

        // Canvas: window + padding, expanded to the requested aspect.
        let needW = windowW + pad * 2, needH = windowH + pad * 2
        var canvasW = needW, canvasH = needH
        if let r = style.aspect.ratio {
            let wFromH = needH * r
            if wFromH >= needW { canvasW = wFromH; canvasH = needH }
            else { canvasW = needW; canvasH = needW / r }
        }
        canvasW = (canvasW / 2).rounded() * 2   // even dims for the encoder
        canvasH = (canvasH / 2).rounded() * 2
        self.canvasSize = CGSize(width: canvasW, height: canvasH)
        self.tilt = max(0, min(style.tilt, 0.18))
        let canvasRect = CGRect(x: 0, y: 0, width: canvasW, height: canvasH)

        // Layout in top-left space, then convert to CI bottom-left.
        let originX = ((canvasW - windowW) / 2).rounded()
        let originTopY = ((canvasH - windowH) / 2).rounded()
        let windowTop = CGRect(x: originX, y: originTopY, width: windowW, height: windowH)
        let screenTop = CGRect(x: originX, y: originTopY + barPx, width: srcW, height: srcH)
        self.screenRectCI = CGRect(x: screenTop.minX, y: canvasH - screenTop.maxY,
                                   width: screenTop.width, height: screenTop.height)

        // Background.
        self.background = Self.makeBackground(style.background, canvas: canvasRect, ci: ci)

        // Chrome bar (full-canvas, clear elsewhere).
        if style.chrome != .none {
            let bar = Self.drawCanvas(width: Int(canvasW), height: Int(canvasH)) { _ in
                Self.drawChrome(style.chrome, barRectTop: CGRect(x: originX, y: originTopY, width: windowW, height: barPx))
            }
            self.chromeBar = bar.map { CIImage(cgImage: $0) }
        } else {
            self.chromeBar = nil
        }

        // Rounded-window alpha mask (full canvas).
        let maskCG = Self.drawCanvas(width: Int(canvasW), height: Int(canvasH)) { _ in
            NSColor.white.setFill()
            NSBezierPath(roundedRect: windowTop, xRadius: style.cornerRadius, yRadius: style.cornerRadius).fill()
        }
        self.windowMask = maskCG.map { CIImage(cgImage: $0) } ?? CIImage(color: .white).cropped(to: canvasRect)

        // Shadow: black where the mask is, blurred + faded, dropped down a touch.
        var base = background
        if style.shadowOpacity > 0, let mask = maskCG {
            let maskCI = CIImage(cgImage: mask)
            let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvasRect)
            var shadow = black.applyingFilter("CISourceInCompositing", parameters: [
                kCIInputBackgroundImageKey: maskCI,
            ])
            shadow = shadow.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: style.shadowBlur])
                .cropped(to: canvasRect)
            shadow = shadow.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(style.shadowOpacity)),
            ])
            shadow = shadow.transformed(by: CGAffineTransform(translationX: 0, y: -style.shadowBlur * 0.25))
            base = shadow.composited(over: background)
        }
        self.baseLayer = base.cropped(to: canvasRect)
    }

    /// `FrameTransform`-compatible: place + composite the live frame into the scene.
    public func transform(_ frame: CIImage, _ t: Double) -> CIImage {
        let canvasRect = CGRect(origin: .zero, size: canvasSize)
        // Normalize the incoming frame to the source size, then drop it into the
        // screen sub-rect.
        let ext = frame.extent
        let sx = sourceSize.width / max(ext.width, 1)
        let sy = sourceSize.height / max(ext.height, 1)
        var screen = frame
            .transformed(by: CGAffineTransform(translationX: -ext.minX, y: -ext.minY))
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: screenRectCI.minX, y: screenRectCI.minY))
            .cropped(to: screenRectCI)

        if let bar = chromeBar { screen = bar.composited(over: screen) }

        var windowed = screen.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: canvasRect),
            kCIInputMaskImageKey: windowMask,
        ])
        // Subtle 3D tilt: narrow the top edge so the window leans back.
        if tilt > 0 {
            let W = canvasRect.width, H = canvasRect.height
            let inset = W * tilt
            windowed = windowed.applyingFilter("CIPerspectiveTransform", parameters: [
                "inputTopLeft": CIVector(x: inset, y: H),
                "inputTopRight": CIVector(x: W - inset, y: H),
                "inputBottomRight": CIVector(x: W, y: 0),
                "inputBottomLeft": CIVector(x: 0, y: 0),
            ]).cropped(to: canvasRect)
        }
        return windowed.composited(over: baseLayer).cropped(to: canvasRect)
    }

    /// Frame a still image into the scene and rasterize to a `CGImage`.
    public static func frameStill(_ image: CGImage, style: SceneStyle) -> CGImage? {
        let comp = SceneCompositor(style: style, sourcePixelSize: CGSize(width: image.width, height: image.height))
        let framed = comp.transform(CIImage(cgImage: image), 0)
        return comp.ci.createCGImage(framed, from: CGRect(origin: .zero, size: comp.canvasSize))
    }

    // MARK: - Static layers

    private static func makeBackground(_ bg: SceneStyle.Background, canvas: CGRect, ci: CIContext) -> CIImage {
        switch bg {
        case .transparent:
            return CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: canvas)
        case let .solid(c):
            return CIImage(color: CIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)).cropped(to: canvas)
        case let .gradient(from, to):
            let g = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: 0, y: canvas.height),
                "inputColor0": CIColor(red: from.r, green: from.g, blue: from.b, alpha: from.a),
                "inputPoint1": CIVector(x: canvas.width, y: 0),
                "inputColor1": CIColor(red: to.r, green: to.g, blue: to.b, alpha: to.a),
            ])
            return (g?.outputImage ?? CIImage(color: .black)).cropped(to: canvas)
        case let .wallpaper(path):
            guard let img = NSImage(contentsOfFile: (path as NSString).expandingTildeInPath),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                return CIImage(color: CIColor(red: 0.05, green: 0.06, blue: 0.12)).cropped(to: canvas)
            }
            let src = CIImage(cgImage: cg)
            // Aspect-fill the canvas.
            let scale = max(canvas.width / src.extent.width, canvas.height / src.extent.height)
            let scaled = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let dx = (canvas.width - scaled.extent.width) / 2 - scaled.extent.minX
            let dy = (canvas.height - scaled.extent.height) / 2 - scaled.extent.minY
            return scaled.transformed(by: CGAffineTransform(translationX: dx, y: dy)).cropped(to: canvas)
        }
    }

    /// Draw into a full-canvas CGImage in top-left space. Only vector fills are
    /// used here (bar + masks), so a manual CTM flip is sufficient and exact —
    /// no `NSImage` backing-scale surprises.
    private static func drawCanvas(width: Int, height: Int, _ body: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        body(ctx)
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// Draw the title bar (traffic lights, and for browsers a URL pill). Assumes
    /// a top-left flipped context; corners are rounded later by the window mask.
    private static func drawChrome(_ chrome: SceneStyle.Chrome, barRectTop r: CGRect) {
        guard chrome != .none else { return }
        NSColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1).setFill()
        NSBezierPath(rect: r).fill()

        let d = min(r.height * 0.34, r.width * 0.02)
        let cy = r.minY + r.height * (chrome == .browser ? 0.32 : 0.5)
        let lights: [NSColor] = [
            NSColor(srgbRed: 1.0, green: 0.37, blue: 0.34, alpha: 1),
            NSColor(srgbRed: 1.0, green: 0.74, blue: 0.18, alpha: 1),
            NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1),
        ]
        var x = r.minX + d * 1.6
        for c in lights {
            c.setFill()
            NSBezierPath(ovalIn: CGRect(x: x, y: cy - d / 2, width: d, height: d)).fill()
            x += d * 1.9
        }

        if chrome == .browser {
            // A URL pill centred on a lower row.
            let pillH = r.height * 0.38
            let pillW = r.width * 0.5
            let pill = CGRect(x: r.midX - pillW / 2, y: r.minY + r.height * 0.52, width: pillW, height: pillH)
            NSColor(srgbRed: 0.22, green: 0.22, blue: 0.25, alpha: 1).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pillH / 2, yRadius: pillH / 2).fill()
        }
    }
}
