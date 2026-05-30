import AppKit
import CoreImage
import CoreGraphics
import Foundation
import AVFoundation

/// Auto-zoom camera tuning. Fully automatic: the camera punches in toward
/// clicks/keystrokes, follows the cursor while zoomed, and eases back out after
/// a spell of inactivity.
public struct CameraStyle: Codable, Sendable, Equatable {
    /// How the zoom moves between wide and in. `smooth` is the lazy cinematic
    /// ease; `punchy` snaps in fast for energetic, quick-cut edits (the "pop").
    public enum Easing: String, Codable, Sendable, CaseIterable, Identifiable {
        case smooth, punchy
        public var id: String { rawValue }
        public var label: String { rawValue.capitalized }
    }

    public var enabled: Bool
    /// Target zoom scale when active (1 = no zoom).
    public var zoom: CGFloat
    /// Smoothing time-constant in seconds (larger = lazier, more cinematic).
    public var smoothing: Double
    /// How long to stay zoomed after the last click/keystroke.
    public var idleHold: Double
    public var easing: Easing

    public init(enabled: Bool = true, zoom: CGFloat = 2.0, smoothing: Double = 0.35,
                idleHold: Double = 1.2, easing: Easing = .smooth) {
        self.enabled = enabled
        self.zoom = zoom
        self.smoothing = smoothing
        self.idleHold = idleHold
        self.easing = easing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        zoom = try c.decodeIfPresent(CGFloat.self, forKey: .zoom) ?? 2.0
        smoothing = try c.decodeIfPresent(Double.self, forKey: .smoothing) ?? 0.35
        idleHold = try c.decodeIfPresent(Double.self, forKey: .idleHold) ?? 1.2
        easing = try c.decodeIfPresent(Easing.self, forKey: .easing) ?? .smooth
    }
}

/// Precomputes the smoothed camera (scale + focus) across the whole timeline
/// from the recorded event track. Offline, so it smooths with a zero-phase
/// (forward+backward) low-pass — the camera can start easing *into* a click
/// slightly before it lands, which is what reads as intentional rather than
/// reactive.
@available(macOS 14.0, *)
final class CameraPlan {
    struct State { var scale: CGFloat; var focus: CGPoint } // focus in CI canvas coords

    private let dt: Double
    private let scales: [CGFloat]
    private let fx: [CGFloat]
    private let fy: [CGFloat]

    init(events: RecordingEvents, screenRectCI: CGRect, canvasSize: CGSize, style: CameraStyle) {
        let fps = max(15, events.fps)
        let dt = 1.0 / Double(fps)
        self.dt = dt
        let n = max(1, Int((events.duration / dt).rounded(.up)) + 1)
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

        func toCanvas(_ fp: CGPoint) -> CGPoint {
            // Recorded-frame pixels (top-left) → CI canvas coords (bottom-left).
            CGPoint(x: screenRectCI.minX + fp.x, y: screenRectCI.maxY - fp.y)
        }
        func focusCanvas(at t: Double) -> CGPoint {
            // Prefer the typing caret when typing is happening, else the cursor.
            if let typed = events.typingFocus(at: t) { return toCanvas(events.framePixel(global: typed)) }
            guard let fp = events.cursorPixel(at: t) else { return center }
            return toCanvas(fp)
        }

        // Clicks/keystrokes are the intent signal. Active within a small
        // anticipation window before, and `idleHold` after.
        let clickTimes = events.clicks.map(\.t) + events.keys.filter(\.down).map(\.t)
        let lead = 0.25
        func isActive(_ t: Double) -> Bool {
            clickTimes.contains { $0 >= t - style.idleHold && $0 <= t + lead }
        }

        var tScale = [CGFloat](repeating: 1, count: n)
        var tFX = [CGFloat](repeating: center.x, count: n)
        var tFY = [CGFloat](repeating: center.y, count: n)
        for i in 0..<n {
            let t = Double(i) * dt
            let active = isActive(t)
            tScale[i] = active ? max(1, style.zoom) : 1
            let f = active ? focusCanvas(at: t) : center
            tFX[i] = f.x; tFY[i] = f.y
        }

        let alpha = CGFloat(dt / (style.smoothing + dt))
        // Punchy snaps the zoom in fast (short time-constant) while the focus
        // pan stays smooth, for an energetic "pop".
        let scaleTau = style.easing == .punchy ? 0.1 : style.smoothing
        let scaleAlpha = CGFloat(dt / (scaleTau + dt))
        self.scales = Self.zeroPhase(tScale, alpha: scaleAlpha)
        self.fx = Self.zeroPhase(tFX, alpha: alpha)
        self.fy = Self.zeroPhase(tFY, alpha: alpha)
    }

    /// Forward then backward exponential smoothing — smooth with no phase lag.
    private static func zeroPhase(_ x: [CGFloat], alpha: CGFloat) -> [CGFloat] {
        guard x.count > 1 else { return x }
        var y = x
        for i in 1..<y.count { y[i] = y[i-1] + alpha * (y[i] - y[i-1]) }
        for i in stride(from: y.count - 2, through: 0, by: -1) { y[i] = y[i+1] + alpha * (y[i] - y[i+1]) }
        return y
    }

    func state(at t: Double) -> State {
        guard !scales.isEmpty else { return State(scale: 1, focus: .zero) }
        let p = max(0, t / dt)
        let i = Int(p)
        if i >= scales.count - 1 {
            return State(scale: scales[scales.count - 1],
                         focus: CGPoint(x: fx[fx.count - 1], y: fy[fy.count - 1]))
        }
        let f = CGFloat(p - Double(i))
        return State(
            scale: scales[i] + (scales[i+1] - scales[i]) * f,
            focus: CGPoint(x: fx[i] + (fx[i+1] - fx[i]) * f, y: fy[i] + (fy[i+1] - fy[i]) * f)
        )
    }
}

/// Combines scene framing (S3) with the auto-zoom camera (S4) into one
/// `FrameTransform`: each frame is framed into the scene, then the smoothed
/// camera zooms/pans the composed canvas toward activity.
@available(macOS 14.0, *)
public final class StudioComposer {
    private let scene: SceneCompositor
    private let camera: CameraPlan?
    public var canvasSize: CGSize { scene.canvasSize }

    // Cursor cinema (S5).
    private let cursor: CursorPlan?
    private let cursorStyle: CursorStyle
    private let cursorImage: CIImage?
    private let cursorSizePx: CGFloat
    private let ringImage: CIImage?
    private let ringBasePx: CGFloat = 256
    private let rippleDuration: Double = 0.5
    private let rippleMaxR: CGFloat
    private let canvasRect: CGRect

    // Keystroke overlay (S6).
    private let keystrokes: KeystrokePlan?
    private let keystrokeArt = KeystrokeArt()
    private let keystrokeStyle: KeystrokeStyle

    // Webcam picture-in-picture (S5.5).
    private let cameraTrack: CameraTrack?
    private let webcamEnabled: Bool
    private let pipRect: CGRect
    private let pipMask: CIImage?

    // Logo bug / watermark (S9).
    private let watermarkImage: CIImage?

    // Timeline overlay layers (S10): the layer spec + its rasterized base image
    // (position/opacity are computed per frame to allow fades + moves).
    private let layerOverlays: [(layer: StudioLayer, base: CIImage)]

    public init(
        style: SceneStyle, camera: CameraStyle?, cursor: CursorStyle? = nil,
        keystrokes: KeystrokeStyle? = nil, webcam: WebcamStyle? = nil,
        cameraTrack: AVAssetTrack? = nil, watermark: String = "", layers: [StudioLayer] = [],
        events: RecordingEvents?, sourcePixelSize: CGSize
    ) {
        let scene = SceneCompositor(style: style, sourcePixelSize: sourcePixelSize)
        self.scene = scene
        self.canvasRect = CGRect(origin: .zero, size: scene.canvasSize)

        if let camera, camera.enabled, camera.zoom > 1.001, let events, !events.cursors.isEmpty {
            self.camera = CameraPlan(events: events, screenRectCI: scene.screenRectCI,
                                     canvasSize: scene.canvasSize, style: camera)
        } else {
            self.camera = nil
        }

        let cs = cursor ?? CursorStyle()
        self.cursorStyle = cs
        self.rippleMaxR = min(scene.canvasSize.width, scene.canvasSize.height) * 0.06
        if cs.enabled, let events, !events.cursors.isEmpty {
            self.cursor = CursorPlan(events: events, screenRectCI: scene.screenRectCI,
                                     canvasSize: scene.canvasSize, style: cs)
            let px = scene.canvasSize.height * 0.05 * cs.size
            self.cursorSizePx = px
            self.cursorImage = CursorArt.pointer(sizePx: px)
            self.ringImage = cs.clickRipples ? CursorArt.ring(sizePx: ringBasePx, color: cs.rippleColor) : nil
        } else {
            self.cursor = nil
            self.cursorSizePx = 0
            self.cursorImage = nil
            self.ringImage = nil
        }

        let ks = keystrokes ?? KeystrokeStyle()
        self.keystrokeStyle = ks
        if ks.enabled, let events, !events.keys.isEmpty {
            self.keystrokes = KeystrokePlan(events: events, style: ks)
        } else {
            self.keystrokes = nil
        }

        let trimmedMark = watermark.trimmingCharacters(in: .whitespacesAndNewlines)
        self.watermarkImage = trimmedMark.isEmpty ? nil
            : Self.textImage(trimmedMark, heightPx: scene.canvasSize.height * 0.035)

        self.layerOverlays = Self.buildLayers(layers, canvas: scene.canvasSize)

        // Webcam PiP layout (static position + rounded mask). Computed whenever
        // the webcam is enabled; the lock-step reader is built only when a track
        // is supplied (render). Preview supplies frames externally (seekable).
        if let webcam, webcam.enabled {
            self.webcamEnabled = true
            self.cameraTrack = cameraTrack.flatMap { CameraTrack(videoTrack: $0) }
            let cw = scene.canvasSize.width, ch = scene.canvasSize.height
            let boxH = ch * webcam.sizeFraction
            let boxW = boxH * 16 / 9
            let m = ch * 0.03
            let x: CGFloat, y: CGFloat
            switch webcam.corner {
            case .bottomRight: x = cw - m - boxW; y = m
            case .bottomLeft:  x = m;             y = m
            case .topRight:    x = cw - m - boxW; y = ch - m - boxH
            case .topLeft:     x = m;             y = ch - m - boxH
            }
            self.pipRect = CGRect(x: x, y: y, width: boxW, height: boxH)
            self.pipMask = Self.roundedMask(width: boxW, height: boxH, radius: boxH * 0.12)?
                .transformed(by: CGAffineTransform(translationX: x, y: y))
        } else {
            self.webcamEnabled = false
            self.cameraTrack = nil
            self.pipRect = .zero
            self.pipMask = nil
        }
    }

    /// White rounded-rect alpha mask at the given pixel size (orientation-agnostic).
    private static func roundedMask(width: CGFloat, height: CGFloat, radius: CGFloat) -> CIImage? {
        let w = Int(width), h = Int(height)
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                           cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
        return ctx.makeImage().map { CIImage(cgImage: $0) }
    }

    /// `externalCamera` lets the editor feed a seeked webcam frame for preview;
    /// the render path leaves it nil and uses the internal lock-step reader.
    public func transform(_ frame: CIImage, _ t: Double, externalCamera: CIImage? = nil) -> CIImage {
        let framed = scene.transform(frame, t)
        let state = camera?.state(at: t) ?? CameraPlan.State(scale: 1, focus: .zero)

        // Camera zoom/pan.
        var img = framed
        if state.scale > 1.001 {
            let f = state.focus
            let tr = CGAffineTransform(translationX: f.x, y: f.y)
                .scaledBy(x: state.scale, y: state.scale)
                .translatedBy(x: -f.x, y: -f.y)
            img = framed.transformed(by: tr).cropped(to: canvasRect)
        }

        if let cursor {
            // Spotlight dim around the (projected) cursor.
            if cursorStyle.spotlight > 0 {
                img = spotlight(img, center: project(cursor.position(at: t), state))
            }
            // Click ripples.
            if cursorStyle.clickRipples, let ring = ringImage {
                for click in cursor.clicks {
                    let age = t - click.t
                    guard age >= 0, age <= rippleDuration else { continue }
                    let prog = CGFloat(age / rippleDuration)
                    img = composite(ring, basePx: ringBasePx, radius: rippleMaxR * prog,
                                    center: project(click.point, state), alpha: 1 - prog, over: img)
                }
            }
            // The cursor itself (tip at the projected position).
            if let cursorImage {
                let a = cursor.alpha(at: t)
                if a > 0.02 {
                    let p = project(cursor.position(at: t), state)
                    img = cursorImage
                        .transformed(by: CGAffineTransform(translationX: p.x, y: p.y - cursorSizePx))
                        .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: a)])
                        .composited(over: img)
                }
            }
        }

        // Webcam picture-in-picture.
        if webcamEnabled, let cam = externalCamera ?? cameraTrack?.frame(at: t) {
            let cw = cam.extent.width, ch = cam.extent.height
            if cw > 0, ch > 0 {
                let scale = max(pipRect.width / cw, pipRect.height / ch)
                let scaled = cam.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                let tx = pipRect.minX + (pipRect.width - cw * scale) / 2 - scaled.extent.minX
                let ty = pipRect.minY + (pipRect.height - ch * scale) / 2 - scaled.extent.minY
                let placed = scaled.transformed(by: CGAffineTransform(translationX: tx, y: ty)).cropped(to: pipRect)
                if let pipMask {
                    let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: canvasRect)
                    img = placed.applyingFilter("CIBlendWithMask", parameters: [
                        kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: pipMask,
                    ]).composited(over: img)
                } else {
                    img = placed.composited(over: img)
                }
            }
        }

        // Keystroke overlay (lower third), drawn above everything else.
        if let keystrokes, let cap = keystrokes.active(at: t) {
            let h = canvasRect.height * 0.06 * keystrokeStyle.size
            if let chips = keystrokeArt.image(for: cap.chips, heightPx: h) {
                let w = chips.extent.width
                let x = (canvasRect.width - w) / 2
                let y = canvasRect.height * 0.06
                img = chips
                    .transformed(by: CGAffineTransform(translationX: x, y: y))
                    .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: cap.alpha)])
                    .composited(over: img)
            }
        }

        // Timeline overlay layers (text / images) active at this time, with
        // fade and optional move.
        for (layer, base) in layerOverlays where layer.isActive(at: t) {
            let op = layer.opacity * layer.fadeFactor(at: t)
            if op < 0.01 { continue }
            let pos = layer.position(at: t)
            let px = CGFloat(pos.x) * canvasRect.width
            let py = CGFloat(1 - pos.y) * canvasRect.height
            var im = base.transformed(by: CGAffineTransform(
                translationX: px - base.extent.width / 2 - base.extent.minX,
                y: py - base.extent.height / 2 - base.extent.minY))
            if op < 0.999 {
                im = im.applyingFilter("CIColorMatrix", parameters: [
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(op))])
            }
            img = im.composited(over: img)
        }

        // Logo bug — bottom-right, subtle, fixed.
        if let mark = watermarkImage {
            let m = canvasRect.height * 0.03
            img = mark
                .transformed(by: CGAffineTransform(translationX: canvasRect.maxX - mark.extent.width - m, y: m))
                .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.6)])
                .composited(over: img)
        }

        return img.cropped(to: canvasRect)
    }

    /// Rasterize each layer's base image once (text drawn, image loaded+scaled).
    /// Position/opacity are applied per frame to allow fades and moves.
    private static func buildLayers(_ layers: [StudioLayer], canvas: CGSize) -> [(layer: StudioLayer, base: CIImage)] {
        layers.compactMap { layer in
            let base: CIImage?
            switch layer.kind {
            case let .text(s):
                base = textImage(s, heightPx: canvas.height * CGFloat(layer.scale), color: layer.color.nsColor)
            case let .image(path):
                guard let ns = NSImage(contentsOfFile: (path as NSString).expandingTildeInPath),
                      let cg = ns.cgImage(forProposedRect: nil, context: nil, hints: nil) else { base = nil; break }
                let src = CIImage(cgImage: cg)
                let scale = (canvas.height * CGFloat(layer.scale)) / max(src.extent.height, 1)
                base = src.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            guard let image = base, image.extent.width > 0 else { return nil }
            return (layer, image)
        }
    }

    /// Overload of `textImage` with a colour (the white-only one is for the bug).
    static func textImage(_ s: String, heightPx: CGFloat, color: NSColor) -> CIImage? {
        let h = max(10, heightPx)
        let font = NSFont.systemFont(ofSize: h * 0.82, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (s as NSString).size(withAttributes: attrs)
        let w = ceil(size.width), hh = ceil(max(size.height, h))
        guard w > 0 else { return nil }
        let img = NSImage(size: NSSize(width: w, height: hh))
        img.lockFocusFlipped(true)
        NSAttributedString(string: s, attributes: attrs).draw(at: NSPoint(x: 0, y: (hh - size.height) / 2))
        img.unlockFocus()
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil).map { CIImage(cgImage: $0) }
    }

    /// Render a string to a CIImage (white semibold), used for the logo bug.
    static func textImage(_ s: String, heightPx: CGFloat) -> CIImage? {
        let h = max(10, heightPx)
        let font = NSFont.systemFont(ofSize: h * 0.82, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let size = (s as NSString).size(withAttributes: attrs)
        let w = ceil(size.width), hh = ceil(max(size.height, h))
        guard w > 0 else { return nil }
        let img = NSImage(size: NSSize(width: w, height: hh))
        img.lockFocusFlipped(true)
        NSAttributedString(string: s, attributes: attrs).draw(at: NSPoint(x: 0, y: (hh - size.height) / 2))
        img.unlockFocus()
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil).map { CIImage(cgImage: $0) }
    }

    /// Map a pre-zoom canvas point through the camera to its on-screen position.
    private func project(_ p: CGPoint, _ s: CameraPlan.State) -> CGPoint {
        CGPoint(x: s.focus.x + (p.x - s.focus.x) * s.scale,
                y: s.focus.y + (p.y - s.focus.y) * s.scale)
    }

    /// Scale a centred art image (ring) to `radius`, fade, place, composite.
    private func composite(_ image: CIImage, basePx: CGFloat, radius: CGFloat,
                           center: CGPoint, alpha: CGFloat, over base: CIImage) -> CIImage {
        let scale = radius / (basePx * 0.42)
        let half = basePx * scale / 2
        let placed = image
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: center.x - half, y: center.y - half))
            .applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha)])
        return placed.composited(over: base)
    }

    private func spotlight(_ image: CIImage, center: CGPoint) -> CIImage {
        let holeR = min(canvasRect.width, canvasRect.height) * 0.18
        let g = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: center.x, y: center.y),
            "inputRadius0": holeR,
            "inputRadius1": holeR * 1.9,
            "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
            "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(cursorStyle.spotlight)),
        ])
        guard let dim = g?.outputImage?.cropped(to: canvasRect) else { return image }
        return dim.composited(over: image)
    }
}
