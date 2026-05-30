import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
import LensCore

/// Drives the Studio editor: owns the per-recording `StudioDocument`, renders
/// the live preview at the scrubber, plays back, and exports (MP4 / GIF). Every
/// document edit rebuilds the preview composer (debounced) so controls feel live.
@available(macOS 14.0, *)
@MainActor
final class StudioEditorModel: ObservableObject {
    let folder: URL

    @Published var doc: StudioDocument { didSet { onDocChanged() } }
    @Published var previewImage: NSImage?
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    @Published var duration: Double = 0
    @Published var exportProgress: Double?
    @Published var status: String?

    private var engine: StudioPreviewEngine?
    private var renderToken = 0
    private var debounce: Task<Void, Never>?
    private var playTimer: Timer?

    init(folder: URL) {
        self.folder = folder
        self.doc = StudioDocument.load(from: folder) ?? StudioEditorModel.defaultDocument()
    }

    /// Seed a new document from the user's current global Studio settings.
    static func defaultDocument() -> StudioDocument {
        let s = LensSettings.shared
        return StudioDocument(scene: s.studioPreset.style, camera: s.cameraStyle, cursor: s.cursorStyle,
                              keystrokes: s.keystrokeStyle, webcam: s.webcamStyle, codec: s.recordingCodec)
    }

    func load() async {
        engine = await StudioPreviewEngine.make(folder: folder, document: doc)
        duration = engine?.duration ?? 0
        if doc.trimEnd == nil { doc.trimEnd = duration }
        await renderNow()
    }

    // MARK: - Preview

    private func onDocChanged() {
        engine?.update(doc)
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self, !Task.isCancelled else { return }
            await self.renderNow()
        }
    }

    func seek(to t: Double) {
        currentTime = min(max(t, 0), max(duration, 0))
        Task { await renderNow() }
    }

    private func renderNow() async {
        guard let engine else { return }
        renderToken += 1
        let token = renderToken
        let t = currentTime
        if let cg = await engine.frame(at: t), token == renderToken {
            previewImage = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        }
    }

    // MARK: - Playback

    func togglePlay() { isPlaying ? pause() : play() }

    func play() {
        guard duration > 0 else { return }
        if currentTime >= (doc.trimEnd ?? duration) - 0.05 { currentTime = doc.trimStart }
        isPlaying = true
        let fps = 20.0
        playTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / fps, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let end = self.doc.trimEnd ?? self.duration
                self.currentTime += 1.0 / fps
                if self.currentTime >= end { self.currentTime = end; self.pause() }
                Task { await self.renderNow() }
            }
        }
    }

    func pause() {
        isPlaying = false
        playTimer?.invalidate(); playTimer = nil
    }

    // MARK: - Save / export

    func save() {
        doc.save(to: folder)
        status = "Saved studio.json"
    }

    func addTextLayer() {
        doc.layers.append(StudioLayer(kind: .text("Text"), start: currentTime, y: 0.5))
    }

    func addImageLayer() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image / sticker"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        doc.layers.append(StudioLayer(kind: .image(url.path), start: currentTime, scale: 0.25))
    }

    func removeLayer(_ id: UUID) { doc.layers.removeAll { $0.id == id } }

    func chooseMusic() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose a background music track"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        doc.music = MusicTrack(path: url.path)
    }

    func export() {
        save()
        exportProgress = 0
        let folder = folder, doc = doc
        Task {
            do {
                let url = try await StudioRenderer.render(session: folder, document: doc) { p in
                    Task { @MainActor in self.exportProgress = p }
                }
                exportProgress = nil
                status = "Exported \(url.lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                exportProgress = nil
                status = "Export failed"
            }
        }
    }

    /// Sample the trimmed range and write an animated GIF.
    func exportGIF(fps: Double = 12) {
        guard let engine else { return }
        exportProgress = 0
        let start = doc.trimStart, end = doc.trimEnd ?? duration
        let out = folder.appendingPathComponent("render.gif")
        Task {
            let frameCount = max(1, Int((end - start) * fps))
            guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
                exportProgress = nil; status = "GIF failed"; return
            }
            CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / fps]] as CFDictionary
            for i in 0..<frameCount {
                let t = start + Double(i) / fps
                if let cg = await engine.frame(at: t) {
                    CGImageDestinationAddImage(dest, cg, frameProps)
                }
                exportProgress = Double(i) / Double(frameCount)
            }
            exportProgress = nil
            if CGImageDestinationFinalize(dest) {
                status = "Exported render.gif"
                NSWorkspace.shared.activateFileViewerSelecting([out])
            } else {
                status = "GIF failed"
            }
        }
    }
}
