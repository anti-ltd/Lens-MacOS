import AVFoundation
import Foundation

/// Records the webcam to its own `camera.mov` alongside the screen recording.
/// The Studio render then composites it as a picture-in-picture bubble. Kept
/// separate from the screen recorder so each can start/stop independently.
@available(macOS 14.0, *)
public final class WebcamRecorder: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let output = AVCaptureMovieFileOutput()
    private var finish: CheckedContinuation<Void, Never>?

    public override init() { super.init() }

    public func start(to url: URL) async throws {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw WebcamError.notAuthorized }
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
                ?? AVCaptureDevice.default(for: .video) else { throw WebcamError.noCamera }

        session.beginConfiguration()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()
        session.startRunning()

        try? FileManager.default.removeItem(at: url)
        output.startRecording(to: url, recordingDelegate: self)
    }

    public func stop() async {
        guard output.isRecording else { session.stopRunning(); return }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finish = c
            output.stopRecording()
        }
        session.stopRunning()
    }

    public func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                           from connections: [AVCaptureConnection], error: Error?) {
        finish?.resume()
        finish = nil
    }

    public enum WebcamError: Error, LocalizedError {
        case notAuthorized, noCamera
        public var errorDescription: String? {
            switch self {
            case .notAuthorized: return "Camera access was denied."
            case .noCamera: return "No camera was found."
            }
        }
    }
}
