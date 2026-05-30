import AVFoundation
import CoreMedia
import CoreGraphics

/// Renders a multi-clip `StudioProject` to a single video: each clip is Studio-
/// rendered to a temp file, then the clips are concatenated back-to-back into one
/// composition (scaled to a common render size) and exported. Single track for
/// now — sequential playback; layered multi-track compositing is S10.
@available(macOS 14.0, *)
public enum ProjectRenderer {

    public enum ProjectError: Error, LocalizedError {
        case noClips, exportFailed
        public var errorDescription: String? {
            switch self {
            case .noClips: return "The project has no enabled clips."
            case .exportFailed: return "Couldn't export the project."
            }
        }
    }

    @discardableResult
    public static func render(
        _ project: StudioProject, to outURL: URL,
        progress: @escaping (Double) -> Void = { _ in }
    ) async throws -> URL {
        let clips = project.enabledClips
        guard !clips.isEmpty else { throw ProjectError.noClips }

        // 1. Studio-render each clip to a temp file.
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("lens-project-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        var rendered: [URL] = []
        for (i, clip) in clips.enumerated() {
            let tmp = tmpDir.appendingPathComponent("clip-\(i).mp4")
            // Prefer the session's saved look (edited in the Studio editor),
            // falling back to the clip's embedded document.
            let doc = StudioDocument.load(from: clip.sessionURL) ?? clip.document
            try await StudioRenderer.render(session: clip.sessionURL, document: doc, to: tmp) { p in
                progress((Double(i) + p) / Double(clips.count) * 0.85)
            }
            rendered.append(tmp)
        }

        // Cross-dissolve path when a transition is set and there's more than one
        // clip. Falls back to a hard-cut concat if the composition export fails.
        if project.transition > 0.01, rendered.count > 1,
           let url = try? await crossDissolve(rendered, transition: project.transition, to: outURL) {
            progress(1)
            return url
        }

        // 2. Concatenate into one composition, scaling each segment to a common
        //    render size (the first clip's).
        let composition = AVMutableComposition()
        guard let vTrack = composition.addMutableTrack(withMediaType: .video,
                                                       preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProjectError.exportFailed
        }
        // Audio track is added lazily — an empty audio track makes the export fail.
        var aTrack: AVMutableCompositionTrack?

        var cursor = CMTime.zero
        var renderSize: CGSize = .zero
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var sizes = Set<String>()

        for url in rendered {
            let asset = AVURLAsset(url: url)
            guard let v = try await asset.loadTracks(withMediaType: .video).first else { continue }
            let dur = try await asset.load(.duration)
            let natural = try await v.load(.naturalSize)
            if renderSize == .zero { renderSize = natural }
            sizes.insert("\(Int(natural.width))x\(Int(natural.height))")

            let range = CMTimeRange(start: .zero, duration: dur)
            try vTrack.insertTimeRange(range, of: v, at: cursor)
            if let a = try await asset.loadTracks(withMediaType: .audio).first {
                if aTrack == nil {
                    aTrack = composition.addMutableTrack(withMediaType: .audio,
                                                         preferredTrackID: kCMPersistentTrackID_Invalid)
                }
                try? aTrack?.insertTimeRange(range, of: a, at: cursor)
            }

            let inst = AVMutableVideoCompositionInstruction()
            inst.timeRange = CMTimeRange(start: cursor, duration: dur)
            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: vTrack)
            layer.setTransform(fitTransform(from: natural, into: renderSize), at: cursor)
            inst.layerInstructions = [layer]
            instructions.append(inst)

            cursor = CMTimeAdd(cursor, dur)
        }
        guard renderSize != .zero else { throw ProjectError.exportFailed }

        // 3. Export. Only attach a video composition (which forces a re-encode
        //    and a render size) when clips actually differ in size; uniform
        //    clips concatenate as-is.
        try? FileManager.default.removeItem(at: outURL)
        guard let export = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ProjectError.exportFailed
        }
        if sizes.count > 1 {
            let videoComposition = AVMutableVideoComposition()
            videoComposition.instructions = instructions
            videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
            videoComposition.renderSize = renderSize
            export.videoComposition = videoComposition
        }

        if #available(macOS 15.0, *) {
            try await export.export(to: outURL, as: .mp4)
        } else {
            export.outputURL = outURL
            export.outputFileType = .mp4
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                export.exportAsynchronously { c.resume() }
            }
            guard export.status == .completed else { throw ProjectError.exportFailed }
        }
        progress(1)
        return outURL
    }

    /// Cross-dissolve consecutive clips: alternate them across two video tracks,
    /// overlap by `transition`, and ramp the outgoing clip's opacity to 0 across
    /// each overlap so the next clip dissolves in.
    private static func crossDissolve(_ urls: [URL], transition: Double, to outURL: URL) async throws -> URL {
        struct Seg { let track: AVMutableCompositionTrack; let range: CMTimeRange; let size: CGSize }
        let comp = AVMutableComposition()
        guard let tA = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let tB = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ProjectError.exportFailed
        }
        var aTrack: AVMutableCompositionTrack?

        // Load tracks first to clamp the transition to the shortest clip.
        var loaded: [(v: AVAssetTrack, dur: CMTime, size: CGSize, audio: AVAssetTrack?)] = []
        for url in urls {
            let asset = AVURLAsset(url: url)
            guard let v = try await asset.loadTracks(withMediaType: .video).first else { continue }
            loaded.append((v, try await asset.load(.duration),
                           try await v.load(.naturalSize),
                           try await asset.loadTracks(withMediaType: .audio).first))
        }
        guard loaded.count > 1 else { throw ProjectError.exportFailed }
        let minDur = loaded.map { $0.dur.seconds }.min() ?? transition
        let T = CMTime(seconds: min(transition, minDur * 0.5), preferredTimescale: 600)

        var segs: [Seg] = []
        var insertAt = CMTime.zero
        let renderSize = loaded[0].size
        for (i, clip) in loaded.enumerated() {
            let track = i % 2 == 0 ? tA : tB
            // Normalize to a single timescale so the instruction boundaries are
            // exactly contiguous (mixed scales produce sub-frame gaps → -12780).
            let dur = CMTimeConvertScale(clip.dur, timescale: 600, method: .roundHalfAwayFromZero)
            let range = CMTimeRange(start: .zero, duration: dur)
            try track.insertTimeRange(range, of: clip.v, at: insertAt)
            if let a = clip.audio {
                if aTrack == nil { aTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }
                try? aTrack?.insertTimeRange(range, of: a, at: insertAt)
            }
            segs.append(Seg(track: track, range: CMTimeRange(start: insertAt, duration: dur), size: clip.size))
            insertAt = CMTimeAdd(insertAt, CMTimeSubtract(dur, T))
        }

        // Build contiguous instructions: solo regions + transition overlaps.
        var insts: [AVMutableVideoCompositionInstruction] = []
        for (i, seg) in segs.enumerated() {
            let soloStart = i == 0 ? seg.range.start : CMTimeAdd(seg.range.start, T)
            let soloEnd = i == segs.count - 1 ? seg.range.end : CMTimeSubtract(seg.range.end, T)
            if soloEnd > soloStart {
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = CMTimeRange(start: soloStart, end: soloEnd)
                let li = AVMutableVideoCompositionLayerInstruction(assetTrack: seg.track)
                if seg.size != renderSize { li.setTransform(fitTransform(from: seg.size, into: renderSize), at: soloStart) }
                inst.layerInstructions = [li]
                insts.append(inst)
            }
            if i < segs.count - 1 {
                let next = segs[i + 1]
                let tr = CMTimeRange(start: CMTimeSubtract(seg.range.end, T), end: seg.range.end)
                let inst = AVMutableVideoCompositionInstruction()
                inst.timeRange = tr
                let outgoing = AVMutableVideoCompositionLayerInstruction(assetTrack: seg.track)
                if seg.size != renderSize { outgoing.setTransform(fitTransform(from: seg.size, into: renderSize), at: tr.start) }
                outgoing.setOpacityRamp(fromStartOpacity: 1, toEndOpacity: 0, timeRange: tr)
                let incoming = AVMutableVideoCompositionLayerInstruction(assetTrack: next.track)
                if next.size != renderSize { incoming.setTransform(fitTransform(from: next.size, into: renderSize), at: tr.start) }
                inst.layerInstructions = [outgoing, incoming] // outgoing on top, fading out
                insts.append(inst)
            }
        }
        insts.sort { $0.timeRange.start < $1.timeRange.start }

        let vc = AVMutableVideoComposition()
        vc.instructions = insts
        vc.frameDuration = CMTime(value: 1, timescale: 30)
        vc.renderSize = renderSize

        try? FileManager.default.removeItem(at: outURL)
        guard let export = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else {
            throw ProjectError.exportFailed
        }
        export.videoComposition = vc
        export.outputURL = outURL
        export.outputFileType = .mp4
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { c.resume() }
        }
        guard export.status == .completed else {
            throw export.error ?? ProjectError.exportFailed
        }
        return outURL
    }

    /// Aspect-fit `source` into `target`, centred.
    private static func fitTransform(from source: CGSize, into target: CGSize) -> CGAffineTransform {
        guard source.width > 0, source.height > 0 else { return .identity }
        let scale = min(target.width / source.width, target.height / source.height)
        let tx = (target.width - source.width * scale) / 2
        let ty = (target.height - source.height * scale) / 2
        return CGAffineTransform(scaleX: scale, y: scale).concatenating(CGAffineTransform(translationX: tx, y: ty))
    }
}
