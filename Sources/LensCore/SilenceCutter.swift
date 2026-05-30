import AVFoundation
import CoreMedia

/// Stitches the keep-intervals (from `SilenceDetector`) of a rendered video into
/// one continuous clip — dropping the collapsed idle gaps. Video + audio are
/// inserted segment by segment into a composition and exported.
@available(macOS 14.0, *)
public enum SilenceCutter {

    public enum CutError: Error { case noVideo, exportFailed }

    @discardableResult
    public static func cut(
        videoURL: URL, keep intervals: [(start: Double, end: Double)], to outURL: URL
    ) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        guard let srcVideo = try await asset.loadTracks(withMediaType: .video).first else { throw CutError.noVideo }
        let srcAudio = try await asset.loadTracks(withMediaType: .audio).first
        let total = try await asset.load(.duration)

        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CutError.exportFailed
        }
        vTrack.preferredTransform = try await srcVideo.load(.preferredTransform)
        let aTrack = srcAudio != nil
            ? comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) : nil

        var cursor = CMTime.zero
        for iv in intervals {
            let s = CMTime(seconds: max(0, iv.start), preferredTimescale: 600)
            var e = CMTime(seconds: iv.end, preferredTimescale: 600)
            if e > total { e = total }
            guard e > s else { continue }
            let range = CMTimeRange(start: s, end: e)
            try vTrack.insertTimeRange(range, of: srcVideo, at: cursor)
            if let srcAudio, let aTrack { try? aTrack.insertTimeRange(range, of: srcAudio, at: cursor) }
            cursor = CMTimeAdd(cursor, range.duration)
        }
        guard cursor > .zero else { throw CutError.exportFailed }

        try? FileManager.default.removeItem(at: outURL)
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            throw CutError.exportFailed
        }
        if #available(macOS 15.0, *) {
            try await export.export(to: outURL, as: .mp4)
        } else {
            export.outputURL = outURL
            export.outputFileType = .mp4
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                export.exportAsynchronously { c.resume() }
            }
            guard export.status == .completed else { throw CutError.exportFailed }
        }
        return outURL
    }
}
