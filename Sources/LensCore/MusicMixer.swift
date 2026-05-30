import AVFoundation
import CoreMedia

/// Mixes a background-music track under a finished video: keeps the original
/// video + its (recording) audio at full volume and adds the music — looped to
/// the video length — at the configured (optionally ducked) volume.
@available(macOS 14.0, *)
public enum MusicMixer {

    public enum MixError: Error { case noVideo, exportFailed }

    /// Write `videoURL` with `music` mixed in to `outURL` (must differ from the
    /// input — exporters can't read and write the same file).
    @discardableResult
    public static func mix(videoURL: URL, music: MusicTrack, to outURL: URL) async throws -> URL {
        let videoAsset = AVURLAsset(url: videoURL)
        guard let srcVideo = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw MixError.noVideo
        }
        let duration = try await videoAsset.load(.duration)
        let full = CMTimeRange(start: .zero, duration: duration)

        let comp = AVMutableComposition()
        guard let vTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw MixError.exportFailed
        }
        try vTrack.insertTimeRange(full, of: srcVideo, at: .zero)
        // preserve the source orientation
        vTrack.preferredTransform = try await srcVideo.load(.preferredTransform)

        // Original recording audio (full volume).
        if let srcAudio = try await videoAsset.loadTracks(withMediaType: .audio).first,
           let aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? aTrack.insertTimeRange(full, of: srcAudio, at: .zero)
        }

        // Music, looped to fill the duration, at the (ducked) volume.
        var inputParams: [AVMutableAudioMixInputParameters] = []
        let musicAsset = AVURLAsset(url: music.url)
        if let srcMusic = try await musicAsset.loadTracks(withMediaType: .audio).first,
           let mTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            let musicDuration = try await musicAsset.load(.duration)
            if musicDuration.seconds > 0.05 {
                var cursor = CMTime.zero
                while cursor < duration {
                    let take = CMTimeMinimum(musicDuration, CMTimeSubtract(duration, cursor))
                    try? mTrack.insertTimeRange(CMTimeRange(start: .zero, duration: take), of: srcMusic, at: cursor)
                    cursor = CMTimeAdd(cursor, take)
                }
                let p = AVMutableAudioMixInputParameters(track: mTrack)
                p.setVolume(music.effectiveVolume, at: .zero)
                inputParams.append(p)
            }
        }

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = inputParams

        try? FileManager.default.removeItem(at: outURL)
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            throw MixError.exportFailed
        }
        export.audioMix = audioMix

        if #available(macOS 15.0, *) {
            try await export.export(to: outURL, as: .mp4)
        } else {
            export.outputURL = outURL
            export.outputFileType = .mp4
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                export.exportAsynchronously { c.resume() }
            }
            guard export.status == .completed else { throw MixError.exportFailed }
        }
        return outURL
    }
}
