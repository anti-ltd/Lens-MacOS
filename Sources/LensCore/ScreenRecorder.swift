import Foundation
import AVFoundation
import CoreMedia
@preconcurrency import ScreenCaptureKit

/// Records the screen — a whole display, a region, or a single window — to an
/// H.264 `.mp4` via ScreenCaptureKit + `AVAssetWriter`. System audio (macOS 13+)
/// and the microphone (macOS 15+) are optional extra tracks. Video frames and
/// audio arrive on a private queue and are appended in real time; the first
/// complete video frame opens the writer session so the timeline starts at zero.
@available(macOS 14.0, *)
public final class ScreenRecorder: NSObject, SCStreamOutput, @unchecked Sendable {

    public private(set) var isRecording = false

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var startedSession = false
    private var outputURL: URL?
    private let queue = DispatchQueue(label: "ltd.anti.lens.recorder")

    public override init() { super.init() }

    /// Record a whole display, or its `cropPixels` region.
    public func startDisplay(
        _ display: SCDisplay,
        cropPixels: CGRect? = nil,
        fps: Int = 60,
        codec: VideoCodec = .h264,
        showsCursor: Bool = true,
        systemAudio: Bool = false,
        microphone: Bool = false,
        to url: URL
    ) async throws {
        let scale = CaptureEngine.scale(for: display)
        let config = makeConfig(fps: fps, showsCursor: showsCursor,
                                systemAudio: systemAudio, microphone: microphone)
        let pxW: Int, pxH: Int
        if let crop = cropPixels {
            config.sourceRect = CGRect(x: crop.minX / scale, y: crop.minY / scale,
                                       width: crop.width / scale, height: crop.height / scale)
            pxW = Int(crop.width); pxH = Int(crop.height)
        } else {
            pxW = Int(CGFloat(display.width) * scale)
            pxH = Int(CGFloat(display.height) * scale)
        }
        config.width = pxW; config.height = pxH
        let filter = SCContentFilter(display: display, excludingWindows: [])
        try await begin(filter: filter, config: config, width: pxW, height: pxH, codec: codec,
                        systemAudio: systemAudio, microphone: microphone, to: url)
    }

    /// Record a single window.
    public func startWindow(
        _ window: SCWindow,
        fps: Int = 60,
        codec: VideoCodec = .h264,
        showsCursor: Bool = false,
        systemAudio: Bool = false,
        microphone: Bool = false,
        scale: CGFloat = 2,
        to url: URL
    ) async throws {
        let config = makeConfig(fps: fps, showsCursor: showsCursor,
                                systemAudio: systemAudio, microphone: microphone)
        let pxW = max(2, Int(window.frame.width * scale))
        let pxH = max(2, Int(window.frame.height * scale))
        config.width = pxW; config.height = pxH
        let filter = SCContentFilter(desktopIndependentWindow: window)
        try await begin(filter: filter, config: config, width: pxW, height: pxH, codec: codec,
                        systemAudio: systemAudio, microphone: microphone, to: url)
    }

    // MARK: - Setup

    private func makeConfig(fps: Int, showsCursor: Bool, systemAudio: Bool, microphone: Bool) -> SCStreamConfiguration {
        let config = SCStreamConfiguration()
        config.showsCursor = showsCursor
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, fps)))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.queueDepth = 6
        if systemAudio {
            config.capturesAudio = true
            config.excludesCurrentProcessAudio = true
        }
        if microphone, #available(macOS 15.0, *) {
            config.captureMicrophone = true
        }
        return config
    }

    private func begin(
        filter: SCContentFilter, config: SCStreamConfiguration,
        width: Int, height: Int, codec: VideoCodec, systemAudio: Bool, microphone: Bool, to url: URL
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let w = try AVAssetWriter(url: url, fileType: .mp4)

        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codec.avCodec,
            AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        video.expectsMediaDataInRealTime = true
        guard w.canAdd(video) else { throw RecorderError.cannotStart }
        w.add(video)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 128_000,
        ]
        var sysInput: AVAssetWriterInput?
        var micrInput: AVAssetWriterInput?
        if systemAudio {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            a.expectsMediaDataInRealTime = true
            if w.canAdd(a) { w.add(a); sysInput = a }
        }
        if microphone, #available(macOS 15.0, *) {
            let m = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            m.expectsMediaDataInRealTime = true
            if w.canAdd(m) { w.add(m); micrInput = m }
        }
        guard w.startWriting() else { throw RecorderError.cannotStart }

        queue.sync {
            self.writer = w
            self.videoInput = video
            self.systemAudioInput = sysInput
            self.micInput = micrInput
            self.outputURL = url
            self.startedSession = false
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        if systemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        }
        if microphone, #available(macOS 15.0, *) {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue)
        }
        try await stream.startCapture()
        self.stream = stream
        isRecording = true
    }

    /// Stop recording and finalize the file. Returns the written URL.
    @discardableResult
    public func stop() async throws -> URL? {
        guard let stream else { return outputURL }
        try? await stream.stopCapture()
        self.stream = nil
        isRecording = false

        let (w, v, s, m, url) = queue.sync {
            (writer, videoInput, systemAudioInput, micInput, outputURL)
        }
        v?.markAsFinished(); s?.markAsFinished(); m?.markAsFinished()
        if let w {
            await withCheckedContinuation { cont in w.finishWriting { cont.resume() } }
        }
        queue.sync {
            writer = nil; videoInput = nil; systemAudioInput = nil; micInput = nil
            outputURL = nil; startedSession = false
        }
        return url
    }

    // MARK: - SCStreamOutput (private queue)

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                       of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }

        if type == .screen {
            guard let video = videoInput, let writer else { return }
            guard let array = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                    as? [[SCStreamFrameInfo: Any]],
                  let raw = array.first?[.status] as? Int,
                  let status = SCFrameStatus(rawValue: raw), status == .complete else { return }
            if !startedSession {
                writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
                startedSession = true
            }
            if video.isReadyForMoreMediaData { video.append(sampleBuffer) }
            return
        }

        // Audio — only once the video session has opened the timeline.
        guard startedSession else { return }
        let input: AVAssetWriterInput?
        if #available(macOS 15.0, *), type == .microphone {
            input = micInput
        } else {
            input = systemAudioInput
        }
        if let input, input.isReadyForMoreMediaData { input.append(sampleBuffer) }
    }

    public enum RecorderError: Error, LocalizedError {
        case cannotStart
        public var errorDescription: String? { "Couldn't start the video recorder." }
    }
}

extension VideoCodec {
    /// The AVFoundation codec for this selection.
    public var avCodec: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        }
    }
}
