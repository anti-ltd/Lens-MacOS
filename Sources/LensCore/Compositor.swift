import AppKit
import CoreImage
import CoreGraphics

/// Turns a raw capture into the final image: applies the active preset's frame
/// constraint (ratio crop or exact pixel resize), bakes in annotations, then
/// wraps the result in its backdrop (fill, padding, rounded corners, shadow).
///
/// All drawing is done through AppKit with a flipped focus so annotation
/// coordinates share the capture's top-left pixel space — the same space the
/// editor reports drags in, so what you draw is what you get.
public enum Compositor {

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// The whole pipeline, in order. Any stage that's a no-op is skipped.
    public static func compose(
        base: CGImage,
        annotations: [Annotation] = [],
        constraint: FrameConstraint = .free,
        backdrop: Backdrop = .none
    ) -> CGImage {
        var image = apply(constraint: constraint, to: base)
        if !annotations.isEmpty {
            image = render(annotations: annotations, on: image)
        }
        if !backdrop.isIdentity {
            image = apply(backdrop: backdrop, to: image)
        }
        return image
    }

    // MARK: - Frame constraint

    /// Ratio constraints centre-crop; pixel constraints resize to exact output.
    public static func apply(constraint: FrameConstraint, to image: CGImage) -> CGImage {
        switch constraint {
        case .free:
            return image
        case let .ratio(w, h):
            guard h > 0 else { return image }
            return cropToAspect(image, aspect: CGFloat(w / h))
        case let .pixels(w, h):
            return resize(image, to: CGSize(width: w, height: h))
        }
    }

    /// Centre-crop to the given aspect ratio (no upscaling — only trims).
    public static func cropToAspect(_ image: CGImage, aspect: CGFloat) -> CGImage {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        guard iw > 0, ih > 0, aspect > 0 else { return image }
        let current = iw / ih
        var cropW = iw, cropH = ih
        if current > aspect {
            cropW = ih * aspect          // too wide — trim sides
        } else if current < aspect {
            cropH = iw / aspect          // too tall — trim top/bottom
        } else {
            return image
        }
        let rect = CGRect(
            x: ((iw - cropW) / 2).rounded(),
            y: ((ih - cropH) / 2).rounded(),
            width: cropW.rounded(),
            height: cropH.rounded()
        )
        return image.cropping(to: rect) ?? image
    }

    /// Resize to exact pixel dimensions (bicubic via Core Image).
    public static func resize(_ image: CGImage, to size: CGSize) -> CGImage {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0, let ctx = context(width: w, height: h) else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }

    // MARK: - Annotations

    /// Bake annotations into the image. Pixel content (the base and the
    /// pixelate/blur regions that sample it) is composited through Core Graphics
    /// at exactly w×h — deterministic and orientation-correct, since `CGContext`
    /// draws a `CGImage` upright. Vector/text marks are drawn into a separate
    /// flipped AppKit overlay (top-left origin, so `NSImage`/`NSBezierPath`/
    /// `NSAttributedString` all share the editor's pixel space) and composited on
    /// top. Mixing a manual CTM flip with `NSImage.draw` was what inverted the
    /// whole viewport — AppKit only draws upright when the context is genuinely
    /// `isFlipped`, which `lockFocusFlipped(true)` provides and a CTM scale does not.
    public static func render(annotations: [Annotation], on image: CGImage) -> CGImage {
        let w = image.width, h = image.height
        guard let ctx = context(width: w, height: h) else { return image }
        let fullRect = CGRect(x: 0, y: 0, width: w, height: h)

        // 1. Base, upright.
        ctx.draw(image, in: fullRect)

        // 2. Sampled effects (pixelate / blur) — Core Image on the base region.
        for a in annotations where a.kind == .pixelate || a.kind == .blur {
            drawFiltered(a, base: image, into: ctx)
        }

        // 3. Vector + text marks — flipped AppKit overlay, then composite.
        let vectors = annotations.filter { $0.kind != .pixelate && $0.kind != .blur }
        if !vectors.isEmpty {
            let overlay = NSImage(size: NSSize(width: w, height: h))
            overlay.lockFocusFlipped(true) // genuine top-left origin
            let baseRect = NSRect(x: 0, y: 0, width: w, height: h)
            for a in vectors { draw(a, in: image, bounds: baseRect) }
            overlay.unlockFocus()
            if let ov = overlay.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                ctx.draw(ov, in: fullRect)
            }
        }

        return ctx.makeImage() ?? image
    }

    private static func draw(_ a: Annotation, in base: CGImage, bounds: NSRect) {
        let color = a.color.nsColor
        switch a.kind {
        case .rectangle:
            color.setStroke()
            let p = NSBezierPath(rect: regionRect(a)); p.lineWidth = a.lineWidth; p.stroke()
        case .ellipse:
            color.setStroke()
            let p = NSBezierPath(ovalIn: regionRect(a)); p.lineWidth = a.lineWidth; p.stroke()
        case .highlight:
            a.color.withAlpha(0.35).nsColor.setFill()
            NSBezierPath(rect: regionRect(a)).fill()
        case .redact:
            color.setFill()
            NSBezierPath(rect: regionRect(a)).fill()
        case .line:
            strokeSegment(a, color: color, arrow: false)
        case .arrow:
            strokeSegment(a, color: color, arrow: true)
        case .freehand:
            strokeFreehand(a, color: color)
        case .text:
            drawText(a)
        case .counter:
            drawCounter(a)
        case .pixelate, .blur:
            break // handled in Core Graphics (drawFiltered) before the overlay
        case .spotlight:
            drawSpotlight(a, bounds: bounds)
        }
    }

    private static func regionRect(_ a: Annotation) -> NSRect {
        guard a.points.count >= 2 else { return .zero }
        let p0 = a.points[0], p1 = a.points[1]
        return NSRect(x: min(p0.x, p1.x), y: min(p0.y, p1.y),
                      width: abs(p1.x - p0.x), height: abs(p1.y - p0.y))
    }

    private static func strokeSegment(_ a: Annotation, color: NSColor, arrow: Bool) {
        guard a.points.count >= 2 else { return }
        let start = a.points[0], end = a.points[1]
        color.setStroke(); color.setFill()
        let path = NSBezierPath()
        path.lineWidth = a.lineWidth
        path.lineCapStyle = .round
        path.move(to: start); path.line(to: end)
        path.stroke()
        guard arrow else { return }
        // Solid triangular head sized off the line width.
        let len = max(a.lineWidth * 3.5, 12)
        let angle = atan2(end.y - start.y, end.x - start.x)
        let spread = CGFloat.pi / 7
        let head = NSBezierPath()
        head.move(to: end)
        head.line(to: CGPoint(x: end.x - len * cos(angle - spread), y: end.y - len * sin(angle - spread)))
        head.line(to: CGPoint(x: end.x - len * cos(angle + spread), y: end.y - len * sin(angle + spread)))
        head.close(); head.fill()
    }

    private static func strokeFreehand(_ a: Annotation, color: NSColor) {
        guard a.points.count >= 2 else { return }
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = a.lineWidth
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.move(to: a.points[0])
        for p in a.points.dropFirst() { path.line(to: p) }
        path.stroke()
    }

    private static func drawText(_ a: Annotation) {
        guard let anchor = a.points.first, !a.text.isEmpty else { return }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: max(a.lineWidth * 5, 18), weight: .semibold),
            .foregroundColor: a.color.nsColor,
        ]
        NSAttributedString(string: a.text, attributes: attrs)
            .draw(at: NSPoint(x: anchor.x, y: anchor.y))
    }

    private static func drawCounter(_ a: Annotation) {
        guard let c = a.points.first else { return }
        let d = max(a.lineWidth * 6, 26)
        let rect = NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)
        a.color.nsColor.setFill()
        NSBezierPath(ovalIn: rect).fill()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: d * 0.55, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let s = NSAttributedString(string: "\(a.number)", attributes: attrs)
        let sz = s.size()
        s.draw(at: NSPoint(x: c.x - sz.width / 2, y: c.y - sz.height / 2))
    }

    /// Pixelate/blur a region by sampling the base, filtering, and drawing the
    /// result back through the Core Graphics context. Annotation coords are
    /// top-left; `CGImage.cropping` is top-left too, while `ctx.draw` is
    /// bottom-left — so the crop uses the region as-is and the draw flips y.
    private static func drawFiltered(_ a: Annotation, base: CGImage, into ctx: CGContext) {
        let region = regionRect(a)
        guard region.width >= 1, region.height >= 1 else { return }
        let cropTL = region.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
        guard !cropTL.isNull, cropTL.width >= 1, cropTL.height >= 1,
              let cut = base.cropping(to: cropTL) else { return }

        let input = CIImage(cgImage: cut)
        let filter: CIFilter?
        if a.kind == .pixelate {
            filter = CIFilter(name: "CIPixellate", parameters: [
                kCIInputImageKey: input,
                kCIInputScaleKey: a.blockSize,
            ])
        } else {
            filter = CIFilter(name: "CIGaussianBlur", parameters: [
                kCIInputImageKey: input.clampedToExtent(),
                kCIInputRadiusKey: max(a.blockSize, 8),
            ])
        }
        guard let output = filter?.outputImage,
              let result = ciContext.createCGImage(output, from: input.extent) else { return }

        let destBL = CGRect(x: cropTL.minX, y: CGFloat(base.height) - cropTL.maxY,
                            width: cropTL.width, height: cropTL.height)
        ctx.draw(result, in: destBL)
    }

    private static func drawSpotlight(_ a: Annotation, bounds: NSRect) {
        let region = regionRect(a)
        NSColor.black.withAlphaComponent(0.55).setFill()
        let path = NSBezierPath(rect: bounds)
        path.appendRect(region)
        path.windingRule = .evenOdd // fill everything except the spotlight
        path.fill()
    }

    // MARK: - Backdrop

    public static func apply(backdrop: Backdrop, to image: CGImage) -> CGImage {
        let iw = CGFloat(image.width), ih = CGFloat(image.height)
        let pad = backdrop.padding
        let outW = Int(iw + pad * 2), outH = Int(ih + pad * 2)
        guard let ctx = context(width: outW, height: outH) else { return image }
        let fullRect = CGRect(x: 0, y: 0, width: outW, height: outH)

        // Background fill (bottom-left coords; gradient runs top-left → bottom-right).
        switch backdrop.fill {
        case .transparent:
            break
        case let .solid(c):
            ctx.setFillColor(c.cgColor); ctx.fill(fullRect)
        case let .gradient(from, to):
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space,
                                  colors: [from.cgColor, to.cgColor] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: outH),
                                       end: CGPoint(x: outW, y: 0), options: [])
            }
        }

        // The image sits centred; CGContext draws a CGImage upright.
        let imageRect = CGRect(x: pad, y: pad, width: iw, height: ih)
        let rounded = CGPath(roundedRect: imageRect,
                             cornerWidth: backdrop.cornerRadius,
                             cornerHeight: backdrop.cornerRadius, transform: nil)

        // Cast the shadow from an opaque rounded plate first (a clip would crop
        // the shadow away), then draw the image clipped to the same corners.
        if backdrop.shadowOpacity > 0 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -backdrop.shadowBlur * 0.3),
                          blur: backdrop.shadowBlur,
                          color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: backdrop.shadowOpacity))
            ctx.addPath(rounded)
            ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            ctx.fillPath()
            ctx.restoreGState()
        }
        ctx.saveGState()
        ctx.addPath(rounded)
        ctx.clip()
        ctx.draw(image, in: imageRect)
        ctx.restoreGState()

        return ctx.makeImage() ?? image
    }

    // MARK: - Low-level

    private static func context(width: Int, height: Int) -> CGContext? {
        CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
    }
}

extension RGBAColor {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    func withAlpha(_ alpha: Double) -> RGBAColor { RGBAColor(r: r, g: g, b: b, a: alpha) }
}
