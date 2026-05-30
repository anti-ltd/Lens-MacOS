import Foundation
import AVFoundation
import CoreImage
import CoreMedia

/// The Studio render spine: decode a raw recording frame by frame, hand each
/// frame to a `transform` (which later stages — scene framing, auto-zoom, cursor
/// cinema — supply), and re-encode the result. Audio tracks pass straight
/// through. At S2 the default transform is identity, so this is a faithful
/// re-encode that proves the pipeline end to end; every later stage just swaps
/// in a richer `transform`.
@available(macOS 14.0, *)
public enum StudioRenderer {

    public enum RenderError: Error, LocalizedError {
        case noVideoTrack, cannotStart, readFailed
        public var errorDescription: String? {
            switch self {
            case .noVideoTrack: return "The recording has no video track."
            case .cannotStart:  return "Couldn't start the render writer."
            case .readFailed:   return "Couldn't read the recording."
            }
        }
    }

    /// A per-frame transform: takes the decoded frame and its presentation time
    /// (seconds) and returns the frame to encode. The returned image should fill
    /// `0..<outputSize` in CIImage (bottom-left) space.
    public typealias FrameTransform = @Sendable (CIImage, Double) -> CIImage

    /// Render `<folder>/screen.mp4` → `<folder>/render.mp4`.
    @discardableResult
    public static func renderSession(
        _ folder: URL,
        codec: VideoCodec = .h264,
        outputSize: CGSize? = nil,
        scene: SceneStyle? = nil,
        camera: CameraStyle? = nil,
        cursor: CursorStyle? = nil,
        keystrokes: KeystrokeStyle? = nil,
        webcam: WebcamStyle? = nil,
        cameraURL: URL? = nil,
        events: RecordingEvents? = nil,
        transform: FrameTransform? = nil,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        let video = folder.appendingPathComponent("screen.mp4")
        let out = folder.appendingPathComponent("render.mp4")
        return try await render(videoURL: video, to: out, codec: codec, outputSize: outputSize,
                                scene: scene, camera: camera, cursor: cursor, keystrokes: keystrokes,
                                webcam: webcam, cameraURL: cameraURL ?? folder.appendingPathComponent("camera.mov"),
                                events: events, transform: transform, progress: progress)
    }

    /// Render `videoURL` to `outURL`, frame by frame.
    @discardableResult
    public static func render(
        videoURL: URL,
        to outURL: URL,
        codec: VideoCodec = .h264,
        outputSize: CGSize? = nil,
        scene: SceneStyle? = nil,
        camera: CameraStyle? = nil,
        cursor: CursorStyle? = nil,
        keystrokes: KeystrokeStyle? = nil,
        webcam: WebcamStyle? = nil,
        cameraURL: URL? = nil,
        watermark: String = "",
        layers: [StudioLayer] = [],
        events: RecordingEvents? = nil,
        trimStart: Double = 0,
        trimEnd: Double? = nil,
        transform: FrameTransform? = nil,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let vTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw RenderError.noVideoTrack
        }
        let natural = try await vTrack.load(.naturalSize)
        let fullDuration = CMTimeGetSeconds(try await asset.load(.duration))
        // Trim window. `start` is offset off output PTS so the clip begins at 0.
        let start = max(0, trimStart)
        let end = (trimEnd.map { $0 > start ? $0 : fullDuration }) ?? fullDuration
        let trimmed = max(0.01, end - start)
        let startCM = CMTime(seconds: start, preferredTimescale: 600)
        let duration = trimmed

        // A scene style builds the framing + auto-zoom + cursor compositor (and
        // its canvas size); otherwise use the supplied transform / output size,
        // defaulting to a faithful re-encode.
        let effectiveTransform: FrameTransform
        let effectiveOutput: CGSize?
        if let scene {
            var camTrack: AVAssetTrack?
            if let webcam, webcam.enabled, let cameraURL {
                camTrack = try? await AVURLAsset(url: cameraURL).loadTracks(withMediaType: .video).first
            }
            let comp = StudioComposer(style: scene, camera: camera, cursor: cursor,
                                      keystrokes: keystrokes, webcam: webcam, cameraTrack: camTrack,
                                      watermark: watermark, layers: layers, events: events, sourcePixelSize: natural)
            effectiveTransform = { img, t in comp.transform(img, t) }
            effectiveOutput = comp.canvasSize
        } else {
            effectiveTransform = transform ?? { img, _ in img }
            effectiveOutput = outputSize
        }
        let outW = Int((effectiveOutput?.width ?? natural.width).rounded())
        let outH = Int((effectiveOutput?.height ?? natural.height).rounded())

        // Reader: decode video to BGRA, audio passthrough.
        let reader = try AVAssetReader(asset: asset)
        let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        vOut.alwaysCopiesSampleData = false
        reader.add(vOut)
        if start > 0 || end < fullDuration {
            reader.timeRange = CMTimeRange(start: startCM, end: CMTime(seconds: end, preferredTimescale: 600))
        }

        let aTracks = try await asset.loadTracks(withMediaType: .audio)
        var aOuts: [AVAssetReaderTrackOutput] = []
        for t in aTracks {
            let o = AVAssetReaderTrackOutput(track: t, outputSettings: nil)
            if reader.canAdd(o) { reader.add(o); aOuts.append(o) }
        }

        // Writer: re-encode video, passthrough audio.
        try? FileManager.default.removeItem(at: outURL)
        let writer = try AVAssetWriter(url: outURL, fileType: .mp4)
        let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec.avCodec, AVVideoWidthKey: outW, AVVideoHeightKey: outH,
        ])
        vIn.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: outW, kCVPixelBufferHeightKey as String: outH,
        ])
        guard writer.canAdd(vIn) else { throw RenderError.cannotStart }
        writer.add(vIn)

        var aIns: [AVAssetWriterInput] = []
        for _ in aOuts {
            let i = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
            i.expectsMediaDataInRealTime = false
            if writer.canAdd(i) { writer.add(i); aIns.append(i) }
        }

        guard reader.startReading() else { throw RenderError.readFailed }
        guard writer.startWriting() else { throw RenderError.cannotStart }
        writer.startSession(atSourceTime: .zero)

        let ci = CIContext()

        // AVFoundation's reader/writer objects aren't Sendable, but each is only
        // ever touched on its own `requestMediaDataWhenReady` queue — wrap them so
        // the @Sendable pump closures can capture them without warnings.
        let vBox = Unchecked((vIn, vOut, adaptor, ci, effectiveTransform, progress))
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()

            // Video.
            group.enter()
            vIn.requestMediaDataWhenReady(on: DispatchQueue(label: "lens.render.video")) {
                let (vIn, vOut, adaptor, ci, xform, progress) = vBox.value
                while vIn.isReadyForMoreMediaData {
                    guard let sb = vOut.copyNextSampleBuffer(),
                          let pb = CMSampleBufferGetImageBuffer(sb) else {
                        vIn.markAsFinished(); group.leave(); return
                    }
                    let pts = CMSampleBufferGetPresentationTimeStamp(sb)
                    let t = CMTimeGetSeconds(pts)
                    let frame = xform(CIImage(cvImageBuffer: pb), t)
                    if let outPB = makePixelBuffer(adaptor: adaptor, width: outW, height: outH) {
                        ci.render(frame, to: outPB)
                        adaptor.append(outPB, withPresentationTime: CMTimeSubtract(pts, startCM))
                    }
                    if duration > 0 { progress(min(1, max(0, (t - start) / duration))) }
                }
            }

            // Audio passthrough (timing shifted by the trim start).
            for (idx, aIn) in aIns.enumerated() {
                let aBox = Unchecked((aIn, aOuts[idx]))
                group.enter()
                aIn.requestMediaDataWhenReady(on: DispatchQueue(label: "lens.render.audio.\(idx)")) {
                    let (aIn, aOut) = aBox.value
                    while aIn.isReadyForMoreMediaData {
                        guard let sb = aOut.copyNextSampleBuffer() else {
                            aIn.markAsFinished(); group.leave(); return
                        }
                        aIn.append(startCM.seconds > 0 ? (Self.shiftTiming(sb, by: startCM) ?? sb) : sb)
                    }
                }
            }

            group.notify(queue: .global()) { cont.resume() }
        }

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        progress(1)
        return outURL
    }

    /// Copy a sample buffer with its presentation time shifted back by `offset`
    /// (used to rebase trimmed audio to a zero-based timeline).
    private static func shiftTiming(_ sb: CMSampleBuffer, by offset: CMTime) -> CMSampleBuffer? {
        var count: CMItemCount = 0
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: max(1, count))
        CMSampleBufferGetSampleTimingInfoArray(sb, entryCount: count, arrayToFill: &timings, entriesNeededOut: &count)
        for i in 0..<timings.count {
            if timings[i].presentationTimeStamp.isValid {
                timings[i].presentationTimeStamp = CMTimeSubtract(timings[i].presentationTimeStamp, offset)
            }
        }
        var out: CMSampleBuffer?
        CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sb,
                                              sampleTimingEntryCount: timings.count,
                                              sampleTimingArray: &timings, sampleBufferOut: &out)
        return out
    }

    /// Render a whole session from its `StudioDocument` — reads `events.json`,
    /// applies every style + trim, writes `render.mp4`.
    @discardableResult
    public static func render(
        session folder: URL, document: StudioDocument,
        to outURL: URL? = nil,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        let events = (try? Data(contentsOf: folder.appendingPathComponent("events.json")))
            .flatMap { try? JSONDecoder().decode(RecordingEvents.self, from: $0) }
        let out = outURL ?? folder.appendingPathComponent("render.mp4")
        _ = try await render(
            videoURL: folder.appendingPathComponent("screen.mp4"), to: out,
            codec: document.codec, scene: document.scene, camera: document.camera,
            cursor: document.cursor, keystrokes: document.keystrokes, webcam: document.webcam,
            cameraURL: folder.appendingPathComponent("camera.mov"),
            watermark: document.watermark, layers: document.layers, events: events,
            trimStart: document.trimStart, trimEnd: document.trimEnd,
            progress: { p in progress(p * 0.8) })

        // Collapse idle gaps (auto-remove-silence) before anything else, so the
        // music/length reflect the cut.
        if document.removeSilence, let events {
            let keep = SilenceDetector.keepIntervals(events: events, trimStart: document.trimStart, trimEnd: document.trimEnd)
            let full = try await AVURLAsset(url: out).load(.duration).seconds
            if SilenceDetector.worthCutting(keep, fullDuration: full) {
                let tmp = out.deletingPathExtension().appendingPathExtension("cut.mp4")
                try await SilenceCutter.cut(videoURL: out, keep: keep, to: tmp)
                try? FileManager.default.removeItem(at: out)
                try FileManager.default.moveItem(at: tmp, to: out)
            }
        }
        progress(0.9)

        // Mix in background music as a post-step (the exporter can't read/write
        // the same file, so mix to a temp and swap it in).
        if let music = document.music, FileManager.default.fileExists(atPath: music.path) {
            let tmp = out.deletingPathExtension().appendingPathExtension("mix.mp4")
            try await MusicMixer.mix(videoURL: out, music: music, to: tmp)
            try? FileManager.default.removeItem(at: out)
            try FileManager.default.moveItem(at: tmp, to: out)
        }

        // Intro / outro title cards — render each as a held clip and concatenate.
        if document.intro != nil || document.outro != nil {
            let size = (try? await AVURLAsset(url: out).loadTracks(withMediaType: .video).first?.load(.naturalSize)) ?? nil
            if let size {
                let cardsDir = out.deletingLastPathComponent()
                var segments: [URL] = []
                if let intro = document.intro, let cg = TitleCardRenderer.image(intro, size: size, background: document.scene.background) {
                    let u = cardsDir.appendingPathComponent("intro.mp4")
                    try await TitleCardRenderer.writeHeld(cg, duration: intro.duration, codec: document.codec, to: u)
                    segments.append(u)
                }
                segments.append(out)
                if let outro = document.outro, let cg = TitleCardRenderer.image(outro, size: size, background: document.scene.background) {
                    let u = cardsDir.appendingPathComponent("outro.mp4")
                    try await TitleCardRenderer.writeHeld(cg, duration: outro.duration, codec: document.codec, to: u)
                    segments.append(u)
                }
                if segments.count > 1 {
                    let tmp = out.deletingPathExtension().appendingPathExtension("titled.mp4")
                    try await VideoConcatenator.concat(segments, to: tmp)
                    try? FileManager.default.removeItem(at: out)
                    try FileManager.default.moveItem(at: tmp, to: out)
                    try? FileManager.default.removeItem(at: cardsDir.appendingPathComponent("intro.mp4"))
                    try? FileManager.default.removeItem(at: cardsDir.appendingPathComponent("outro.mp4"))
                }
            }
        }
        progress(1)
        return out
    }

    /// Carries non-Sendable AVFoundation objects across a `@Sendable` boundary.
    /// Safe here because each boxed object is used on exactly one serial queue.
    private final class Unchecked<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }

    /// A pixel buffer from the adaptor's pool, or a freshly created one.
    private static func makePixelBuffer(
        adaptor: AVAssetWriterInputPixelBufferAdaptor, width: Int, height: Int
    ) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        if let pool = adaptor.pixelBufferPool {
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        }
        if pb == nil {
            CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                [kCVPixelBufferCGImageCompatibilityKey: true,
                                 kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pb)
        }
        return pb
    }
}
