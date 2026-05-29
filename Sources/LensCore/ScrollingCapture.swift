import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// Long-page capture: grab a region, scroll it, grab again, and stitch the
/// frames into one tall image by detecting the vertical overlap between
/// consecutive frames. Works on any scrollable surface — a web page, a chat, a
/// document — because it drives real scroll-wheel events rather than asking the
/// app for anything.
@available(macOS 14.0, *)
public enum ScrollingCapture {

    /// Capture `regionPixels` (in `display` pixel space, top-left origin) while
    /// scrolling at `globalPoint` (global top-left points), stitching the result.
    /// Stops when a scroll reveals nothing new or `maxFrames` is hit.
    public static func capture(
        display: SCDisplay,
        regionPixels: CGRect,
        at globalPoint: CGPoint,
        showCursor: Bool = false,
        maxFrames: Int = 60,
        settle: UInt64 = 280_000_000   // ns between scroll and grab
    ) async throws -> CGImage {
        var frames: [Bitmap] = []
        var deltas: [Int] = []         // new rows contributed by each frame after the first

        for i in 0..<maxFrames {
            let cg = try await CaptureEngine.captureDisplay(display, showCursor: showCursor, cropPixels: regionPixels)
            guard let bmp = Bitmap(cg) else { break }

            if let last = frames.last {
                let d = overlapDelta(top: last, bottom: bmp)
                if d <= 1 { break }    // nothing new revealed — we've hit the bottom
                deltas.append(d)
            }
            frames.append(bmp)

            // Scroll down by roughly one viewport-minus-overlap so the next grab
            // advances but still shares a band to align against. Negative deltaY
            // scrolls content up (i.e. page moves down).
            if i < maxFrames - 1 {
                postScroll(at: globalPoint, lines: -10)
                try? await Task.sleep(nanoseconds: settle)
            }
        }

        guard let first = frames.first else { throw CaptureEngine.CaptureError.noContent }
        if let stitched = stitch(frames: frames, deltas: deltas) { return stitched }
        if let single = first.cgImage() { return single }
        throw CaptureEngine.CaptureError.noContent
    }

    // MARK: - Scroll events

    private static func postScroll(at point: CGPoint, lines: Int32) {
        // Move the cursor to the target first so the scroll lands on the right
        // view, then post a line-based wheel event.
        CGWarpMouseCursorPosition(point)
        if let ev = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                            wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0) {
            ev.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Overlap detection

    /// Rows of new content `bottom` adds below `top`. Found by sliding `bottom`
    /// up against `top` and scoring the overlap; the best low-error shift is the
    /// scroll delta. Returns 0 when the frames are effectively identical.
    private static func overlapDelta(top: Bitmap, bottom: Bitmap) -> Int {
        guard top.width == bottom.width, top.height == bottom.height, top.height > 8 else { return 0 }
        let h = top.height
        let minShift = max(2, h / 40)              // ignore sub-pixel jitter
        let maxShift = h - max(8, h / 10)          // keep a real overlap band
        var bestShift = 0
        var bestScore = Double.greatestFiniteMagnitude

        let rowStride = max(1, h / 120)
        for d in stride(from: minShift, through: maxShift, by: max(1, (maxShift - minShift) / 80 + 1)) {
            let score = rowError(top: top, bottom: bottom, shift: d, rowStride: rowStride)
            if score < bestScore { bestScore = score; bestShift = d }
        }
        // High residual error means no good alignment — treat as fully new page.
        if bestScore > 38 { return h }
        return bestShift
    }

    /// Mean per-channel error comparing top[y+shift] against bottom[y] over the
    /// overlap, sampling columns for speed.
    private static func rowError(top: Bitmap, bottom: Bitmap, shift: Int, rowStride: Int) -> Double {
        let h = top.height, w = top.width
        let colStride = max(1, w / 64)
        var sum = 0.0, count = 0.0
        var y = 0
        while y + shift < h {
            let tRow = (y + shift) * top.bytesPerRow
            let bRow = y * bottom.bytesPerRow
            var x = 0
            while x < w {
                let ti = tRow + x * 4, bi = bRow + x * 4
                sum += abs(Double(top.data[ti]) - Double(bottom.data[bi]))
                sum += abs(Double(top.data[ti + 1]) - Double(bottom.data[bi + 1]))
                sum += abs(Double(top.data[ti + 2]) - Double(bottom.data[bi + 2]))
                count += 3
                x += colStride
            }
            y += rowStride
        }
        return count == 0 ? .greatestFiniteMagnitude : sum / count
    }

    // MARK: - Stitch

    private static func stitch(frames: [Bitmap], deltas: [Int]) -> CGImage? {
        guard let first = frames.first else { return nil }
        let w = first.width
        let totalH = first.height + deltas.reduce(0, +)
        let out = NSImage(size: NSSize(width: w, height: totalH))
        out.lockFocusFlipped(true)
        defer { out.unlockFocus() }

        // First frame in full at the top.
        if let cg = first.cgImage() {
            NSImage(cgImage: cg, size: NSSize(width: w, height: first.height))
                .draw(in: NSRect(x: 0, y: 0, width: w, height: first.height))
        }
        var yOffset = first.height
        for (idx, d) in deltas.enumerated() {
            let frame = frames[idx + 1]
            guard let cg = frame.cgImage(),
                  let tail = cg.cropping(to: CGRect(x: 0, y: frame.height - d, width: w, height: d)) else { continue }
            NSImage(cgImage: tail, size: NSSize(width: w, height: d))
                .draw(in: NSRect(x: 0, y: yOffset, width: w, height: d))
            yOffset += d
        }
        return out.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}

/// A flat RGBA8 pixel buffer for fast comparison/cropping during stitching.
struct Bitmap {
    let width: Int
    let height: Int
    let bytesPerRow: Int
    var data: [UInt8]

    init?(_ image: CGImage) {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        let bpr = w * 4
        var buf = [UInt8](repeating: 0, count: bpr * h)
        let ok = buf.withUnsafeMutableBytes { ptr -> Bool in
            guard let ctx = CGContext(data: ptr.baseAddress, width: w, height: h,
                      bitsPerComponent: 8, bytesPerRow: bpr,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            // Flip so buffer row 0 is the *top* of the image — the overlap logic
            // and tail-cropping below both reason in top-left space.
            ctx.translateBy(x: 0, y: CGFloat(h))
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        self.width = w; self.height = h; self.bytesPerRow = bpr; self.data = buf
    }

    /// Reconstruct a `CGImage` from the top-down buffer. `CGImage`'s data is
    /// interpreted top-to-bottom, so no second flip is needed.
    func cgImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}
