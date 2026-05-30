import AVFoundation
import CoreImage
import LensCore

/// Renders a single composed Studio frame at an arbitrary time — the editor's
/// preview. Uses seekable `AVAssetImageGenerator`s for the screen and webcam
/// (random access for scrubbing), feeding the webcam frame into the composer
/// externally. Rebuilds the composer when the document changes.
@available(macOS 14.0, *)
final class StudioPreviewEngine: @unchecked Sendable {
    let duration: Double
    private let sourceSize: CGSize
    private let events: RecordingEvents?
    private let screenGen: AVAssetImageGenerator
    private let camGen: AVAssetImageGenerator?
    private let ci = CIContext()
    private var composer: StudioComposer
    private var webcamEnabled: Bool

    static func make(folder: URL, document: StudioDocument) async -> StudioPreviewEngine? {
        let screen = AVURLAsset(url: folder.appendingPathComponent("screen.mp4"))
        guard let track = try? await screen.loadTracks(withMediaType: .video).first,
              let natural = try? await track.load(.naturalSize),
              let dur = try? await screen.load(.duration) else { return nil }

        let events = (try? Data(contentsOf: folder.appendingPathComponent("events.json")))
            .flatMap { try? JSONDecoder().decode(RecordingEvents.self, from: $0) }

        let sg = AVAssetImageGenerator(asset: screen)
        sg.appliesPreferredTrackTransform = true
        sg.requestedTimeToleranceBefore = .zero
        sg.requestedTimeToleranceAfter = .zero

        var camGen: AVAssetImageGenerator?
        let camURL = folder.appendingPathComponent("camera.mov")
        if FileManager.default.fileExists(atPath: camURL.path) {
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: camURL))
            g.appliesPreferredTrackTransform = true
            camGen = g
        }

        return StudioPreviewEngine(duration: CMTimeGetSeconds(dur), sourceSize: natural, events: events,
                                   screenGen: sg, camGen: camGen, document: document)
    }

    private init(duration: Double, sourceSize: CGSize, events: RecordingEvents?,
                 screenGen: AVAssetImageGenerator, camGen: AVAssetImageGenerator?, document: StudioDocument) {
        self.duration = duration
        self.sourceSize = sourceSize
        self.events = events
        self.screenGen = screenGen
        self.camGen = camGen
        self.webcamEnabled = document.webcam.enabled
        self.composer = StudioComposer(
            style: document.scene, camera: document.camera, cursor: document.cursor,
            keystrokes: document.keystrokes, webcam: document.webcam, cameraTrack: nil,
            watermark: document.watermark, layers: document.layers,
            events: events, sourcePixelSize: sourceSize)
    }

    /// Rebuild the composer for an edited document (styles changed).
    func update(_ document: StudioDocument) {
        webcamEnabled = document.webcam.enabled
        composer = StudioComposer(
            style: document.scene, camera: document.camera, cursor: document.cursor,
            keystrokes: document.keystrokes, webcam: document.webcam, cameraTrack: nil,
            watermark: document.watermark, layers: document.layers,
            events: events, sourcePixelSize: sourceSize)
    }

    var canvasSize: CGSize { composer.canvasSize }

    /// Compose the frame at `t`.
    func frame(at t: Double) async -> CGImage? {
        let time = CMTime(seconds: max(0, t), preferredTimescale: 600)
        guard let screen = try? await screenGen.image(at: time).image else { return nil }

        var cam: CIImage?
        if webcamEnabled, let camGen, let cg = try? await camGen.image(at: time).image {
            cam = CIImage(cgImage: cg)
        }
        let out = composer.transform(CIImage(cgImage: screen), t, externalCamera: cam)
        return ci.createCGImage(out, from: CGRect(origin: .zero, size: composer.canvasSize))
    }
}
