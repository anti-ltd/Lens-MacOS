import AVFoundation
import CoreMedia

/// Concatenates equal-size video segments (e.g. intro card + main clip + outro
/// card) into one file. Audio is carried per-segment where present, so silent
/// title cards leave gaps and the main clip's audio plays at its offset.
@available(macOS 14.0, *)
public enum VideoConcatenator {

    public enum ConcatError: Error { case empty, exportFailed }

    @discardableResult
    public static func concat(_ urls: [URL], to outURL: URL) async throws -> URL {
        guard !urls.isEmpty else { throw ConcatError.empty }
        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ConcatError.exportFailed
        }
        var aTrack: AVMutableCompositionTrack?
        var cursor = CMTime.zero
        var didSetTransform = false

        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let v = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let dur = try await asset.load(.duration)
            let range = CMTimeRange(start: .zero, duration: dur)
            try vTrack.insertTimeRange(range, of: v, at: cursor)
            if !didSetTransform { vTrack.preferredTransform = try await v.load(.preferredTransform); didSetTransform = true }
            if let a = try await asset.loadTracks(withMediaType: .audio).first {
                if aTrack == nil {
                    aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                try? aTrack?.insertTimeRange(range, of: a, at: cursor)
            }
            cursor = CMTimeAdd(cursor, dur)
        }
        guard cursor > .zero else { throw ConcatError.exportFailed }

        try? FileManager.default.removeItem(at: outURL)
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            throw ConcatError.exportFailed
        }
        if #available(macOS 15.0, *) {
            try await export.export(to: outURL, as: .mp4)
        } else {
            export.outputURL = outURL
            export.outputFileType = .mp4
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                export.exportAsynchronously { c.resume() }
            }
            guard export.status == .completed else { throw ConcatError.exportFailed }
        }
        return outURL
    }
}
