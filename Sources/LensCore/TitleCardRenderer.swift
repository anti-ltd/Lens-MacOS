import AppKit
import AVFoundation
import CoreImage
import CoreMedia

/// Renders intro/outro title cards (and holds them as short video segments) so
/// they can be concatenated with the main clip.
@available(macOS 14.0, *)
public enum TitleCardRenderer {

    /// Draw a centred title + subtitle over the scene's background.
    public static func image(_ card: TitleCard, size: CGSize, background: SceneStyle.Background) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard w > 0, h > 0 else { return nil }
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocusFlipped(true)

        let rect = NSRect(x: 0, y: 0, width: w, height: h)
        switch background {
        case .transparent, .solid:
            NSColor(srgbRed: 0.05, green: 0.06, blue: 0.12, alpha: 1).setFill(); rect.fill()
            if case let .solid(c) = background { c.nsColor.setFill(); rect.fill() }
        case let .gradient(from, to):
            NSGradient(starting: from.nsColor, ending: to.nsColor)?.draw(in: rect, angle: -90)
        case .wallpaper:
            NSColor(srgbRed: 0.05, green: 0.06, blue: 0.12, alpha: 1).setFill(); rect.fill()
        }

        let titleFont = NSFont.systemFont(ofSize: size.height * 0.11, weight: .bold)
        let subFont = NSFont.systemFont(ofSize: size.height * 0.05, weight: .regular)
        let title = NSAttributedString(string: card.title, attributes: [
            .font: titleFont, .foregroundColor: NSColor.white])
        let sub = NSAttributedString(string: card.subtitle, attributes: [
            .font: subFont, .foregroundColor: NSColor.white.withAlphaComponent(0.75)])

        let ts = title.size()
        let ss = card.subtitle.isEmpty ? .zero : sub.size()
        let gap: CGFloat = card.subtitle.isEmpty ? 0 : size.height * 0.03
        let blockH = ts.height + gap + ss.height
        let y = (size.height - blockH) / 2
        title.draw(at: NSPoint(x: (size.width - ts.width) / 2, y: y + ss.height + gap))
        if !card.subtitle.isEmpty {
            sub.draw(at: NSPoint(x: (size.width - ss.width) / 2, y: y))
        }
        img.unlockFocus()
        return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    /// Write a still held for `card.duration` as a short H.264 clip.
    public static func writeHeld(_ image: CGImage, duration: Double, fps: Int = 30,
                                 codec: VideoCodec = .h264, to url: URL) async throws {
        let w = image.width, h = image.height
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(url: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec.avCodec, AVVideoWidthKey: w, AVVideoHeightKey: h])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: w, kCVPixelBufferHeightKey as String: h])
        writer.add(input)
        guard writer.startWriting() else { throw RenderError.cannotStart }
        writer.startSession(atSourceTime: .zero)

        let pb = pixelBuffer(from: image)
        let frames = max(1, Int(duration * Double(fps)))
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 2_000_000) }
            if let pb { adaptor.append(pb, withPresentationTime: CMTime(value: Int64(i), timescale: Int32(fps))) }
        }
        input.markAsFinished()
        await withCheckedContinuation { c in writer.finishWriting { c.resume() } }
    }

    private static func pixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: true,
                     kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary
        CVPixelBufferCreate(nil, image.width, image.height, kCVPixelFormatType_32BGRA, attrs, &pb)
        guard let pb else { return nil }
        let ci = CIContext()
        ci.render(CIImage(cgImage: image), to: pb)
        return pb
    }

    enum RenderError: Error { case cannotStart }
}
