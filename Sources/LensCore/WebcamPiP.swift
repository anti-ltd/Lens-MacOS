import AVFoundation
import CoreImage
import CoreGraphics

/// Picture-in-picture webcam styling for Studio renders.
public struct WebcamStyle: Codable, Sendable, Equatable {
    public enum Corner: String, Codable, Sendable, CaseIterable, Identifiable {
        case bottomRight, bottomLeft, topRight, topLeft
        public var id: String { rawValue }
        public var label: String {
            switch self {
            case .bottomRight: return "Bottom Right"
            case .bottomLeft: return "Bottom Left"
            case .topRight: return "Top Right"
            case .topLeft: return "Top Left"
            }
        }
    }
    public var enabled: Bool
    /// Bubble height as a fraction of the canvas height.
    public var sizeFraction: CGFloat
    public var corner: Corner

    public init(enabled: Bool = false, sizeFraction: CGFloat = 0.24, corner: Corner = .bottomRight) {
        self.enabled = enabled
        self.sizeFraction = sizeFraction
        self.corner = corner
    }
}

/// A lock-step reader over `camera.mov`: `frame(at:)` returns the latest webcam
/// frame whose timestamp is ≤ the requested time, advancing as the render walks
/// the timeline forward. Avoids decoding the whole camera track into memory.
@available(macOS 14.0, *)
final class CameraTrack {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var current: CIImage?
    private var pending: CIImage?
    private var pendingPTS: Double = -1

    init?(videoTrack: AVAssetTrack) {
        guard let asset = videoTrack.asset, let r = try? AVAssetReader(asset: asset) else { return nil }
        let o = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        o.alwaysCopiesSampleData = false
        guard r.canAdd(o) else { return nil }
        r.add(o)
        guard r.startReading() else { return nil }
        reader = r; output = o
        decodeNext()
    }

    private func decodeNext() {
        if let sb = output.copyNextSampleBuffer(), let pb = CMSampleBufferGetImageBuffer(sb) {
            pendingPTS = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sb))
            pending = CIImage(cvImageBuffer: pb)
        } else {
            pending = nil
            pendingPTS = .infinity
        }
    }

    func frame(at t: Double) -> CIImage? {
        while pending != nil, pendingPTS <= t {
            current = pending
            decodeNext()
        }
        return current
    }
}
