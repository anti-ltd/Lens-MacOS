import AppKit
import SwiftUI
import ApplicationServices
import LensCore
@preconcurrency import ScreenCaptureKit

/// The conductor. A capture mode comes in (from a hotkey or the menu); this
/// drives the right flow — overlay, engine call, compose, route to destination —
/// and surfaces permission problems. Everything runs on the main actor; the
/// ScreenCaptureKit calls hop to background via `async` but resolve back here.
@MainActor
public final class CaptureController {
    public static let shared = CaptureController()
    private init() {}

    /// A raw capture plus the preset that governs its framing and backdrop.
    struct Capture {
        var image: CGImage
        var preset: Preset
    }

    private var areaOverlay: AreaSelectionController?
    private var windowPicker: WindowPickerController?
    private var colorLoupe: ColorLoupeController?

    // Video recording state.
    private var recorder: ScreenRecorder?
    private var recordingStart: Date?
    private var tracker: RecordingTracker?
    private var recordingFileURL: URL?
    private var webcamRecorder: WebcamRecorder?
    public var isRecording: Bool { recorder?.isRecording ?? false }

    // MARK: - Entry

    public func perform(_ mode: CaptureMode) {
        let preset = LensSettings.shared.activePreset
        switch mode {
        case .fullScreen:  captureFullScreen(preset: preset)
        case .area:        captureArea(preset: preset)
        case .window:      captureWindow(preset: preset)
        case .scrolling:   captureScrolling(preset: preset)
        case .colorPicker: pickColor()
        case .video:       toggleRecording()
        }
    }

    // MARK: - Modes

    private func captureFullScreen(preset: Preset) {
        let point = globalCGPoint()
        runCapture {
            let content = try await CaptureEngine.shareableContent()
            guard let display = CaptureEngine.display(containing: point, in: content) else {
                throw CaptureEngine.CaptureError.noDisplay
            }
            let image = try await CaptureEngine.captureDisplay(
                display, showCursor: LensSettings.shared.captureCursor
            )
            return Capture(image: image, preset: preset)
        }
    }

    private func captureArea(preset: Preset) {
        let controller = AreaSelectionController(aspect: preset.constraint.aspect)
        areaOverlay = controller
        controller.begin { [weak self] result in
            self?.areaOverlay = nil
            guard let result else { return }
            self?.runCapture {
                let image = try await CaptureEngine.captureDisplay(
                    result.display,
                    showCursor: LensSettings.shared.captureCursor,
                    cropPixels: result.cropPixels
                )
                return Capture(image: image, preset: preset)
            }
        }
    }

    private func captureWindow(preset: Preset) {
        let controller = WindowPickerController()
        windowPicker = controller
        Task {
            do {
                let content = try await CaptureEngine.shareableContent()
                controller.begin(windows: content.windows) { [weak self] picked in
                    self?.windowPicker = nil
                    guard let picked else { return }
                    self?.runCapture {
                        let scale = NSScreen.main?.backingScaleFactor ?? 2
                        let image = try await CaptureEngine.captureWindow(
                            picked, showCursor: false, scale: scale
                        )
                        return Capture(image: image, preset: preset)
                    }
                }
            } catch {
                self.windowPicker = nil
                self.handle(error)
            }
        }
    }

    private func captureScrolling(preset: Preset) {
        // Scrolling capture drives synthetic scroll events; without Accessibility
        // trust those events go nowhere and we'd stitch one motionless frame.
        guard Self.hasAccessibilityPermission() else {
            promptForAccessibility(reason: "Scrolling capture needs Accessibility access to scroll the page for you.")
            return
        }
        let controller = AreaSelectionController(aspect: nil, prompt: "Drag over the scrollable area")
        areaOverlay = controller
        controller.begin { [weak self] result in
            self?.areaOverlay = nil
            guard let result else { return }
            let globalPoint = result.globalCenter
            self?.runCapture {
                let image = try await ScrollingCapture.capture(
                    display: result.display,
                    regionPixels: result.cropPixels,
                    at: globalPoint
                )
                return Capture(image: image, preset: preset)
            }
        }
    }

    private func pickColor() {
        let controller = ColorLoupeController()
        colorLoupe = controller
        Task {
            do {
                let point = globalCGPoint()
                let content = try await CaptureEngine.shareableContent()
                guard let display = CaptureEngine.display(containing: point, in: content) else { return }
                let image = try await CaptureEngine.captureDisplay(display, showCursor: false)
                controller.begin(displayImage: image, screen: screenUnderMouse()) { [weak self] hex in
                    self?.colorLoupe = nil
                    guard let hex else { return }
                    OutputWriter.copyToClipboard(text: hex)
                    CaptureFeedback.toast("Copied \(hex)")
                }
            } catch {
                self.colorLoupe = nil
                self.handle(error)
            }
        }
    }

    // MARK: - Video recording

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    /// Start a recording, picking the source first when it's a region or window.
    private func startRecording() {
        let url = recordingURL()
        switch LensSettings.shared.recordingSource {
        case .fullScreen:
            let point = globalCGPoint()
            Task {
                do {
                    let content = try await CaptureEngine.shareableContent()
                    guard let display = CaptureEngine.display(containing: point, in: content) else {
                        throw CaptureEngine.CaptureError.noDisplay
                    }
                    try await self.beginRecording(display: display, cropPixels: nil, url: url)
                } catch { self.failRecording(error) }
            }

        case .region:
            let controller = AreaSelectionController(aspect: nil, prompt: "Drag the area to record • Esc to cancel")
            areaOverlay = controller
            controller.begin { [weak self] result in
                self?.areaOverlay = nil
                guard let self, let result else { return }
                Task {
                    do { try await self.beginRecording(display: result.display, cropPixels: result.cropPixels, url: url) }
                    catch { self.failRecording(error) }
                }
            }

        case .window:
            let controller = WindowPickerController()
            windowPicker = controller
            Task {
                do {
                    let content = try await CaptureEngine.shareableContent()
                    controller.begin(windows: content.windows) { [weak self] picked in
                        self?.windowPicker = nil
                        guard let self, let picked else { return }
                        Task {
                            do { try await self.beginRecording(window: picked, url: url) }
                            catch { self.failRecording(error) }
                        }
                    }
                } catch { self.windowPicker = nil; self.failRecording(error) }
            }
        }
    }

    private func beginRecording(display: SCDisplay, cropPixels: CGRect?, url: URL) async throws {
        let s = LensSettings.shared
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rec = ScreenRecorder()
        recorder = rec
        try await rec.startDisplay(display, cropPixels: cropPixels, fps: s.recordingFPS.rawValue,
                                   codec: s.recordingCodec, showsCursor: s.recordCursor,
                                   systemAudio: s.recordSystemAudio, microphone: s.recordMicrophone, to: url)

        // Studio event track (cursor / clicks / keys) for the render pass.
        let scale = CaptureEngine.scale(for: display)
        let region: CGRect
        let pixelSize: CGSize
        if let crop = cropPixels {
            region = CGRect(x: display.frame.minX + crop.minX / scale, y: display.frame.minY + crop.minY / scale,
                            width: crop.width / scale, height: crop.height / scale)
            pixelSize = crop.size
        } else {
            region = display.frame
            pixelSize = CGSize(width: CGFloat(display.width) * scale, height: CGFloat(display.height) * scale)
        }
        startTracking(url: url, region: region, scale: scale, pixelSize: pixelSize, fps: s.recordingFPS.rawValue)
        presentRecordingIndicator()
    }

    private func beginRecording(window: SCWindow, url: URL) async throws {
        let s = LensSettings.shared
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rec = ScreenRecorder()
        recorder = rec
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        try await rec.startWindow(window, fps: s.recordingFPS.rawValue, codec: s.recordingCodec,
                                  showsCursor: s.recordCursor,
                                  systemAudio: s.recordSystemAudio, microphone: s.recordMicrophone,
                                  scale: scale, to: url)
        let pixelSize = CGSize(width: window.frame.width * scale, height: window.frame.height * scale)
        startTracking(url: url, region: window.frame, scale: scale, pixelSize: pixelSize, fps: s.recordingFPS.rawValue)
        presentRecordingIndicator()
    }

    private func startTracking(url: URL, region: CGRect, scale: CGFloat, pixelSize: CGSize, fps: Int) {
        recordingFileURL = url
        let t = RecordingTracker()
        t.begin(regionGlobalPoints: region, scale: scale, pixelSize: pixelSize, fps: fps)
        tracker = t

        // Webcam captured to camera.mov in the session folder for the PiP.
        if LensSettings.shared.studioWebcam {
            let camURL = url.deletingLastPathComponent().appendingPathComponent("camera.mov")
            let wr = WebcamRecorder()
            webcamRecorder = wr
            Task { try? await wr.start(to: camURL) }
        }
    }

    private func presentRecordingIndicator() {
        let start = Date()
        recordingStart = start
        if LensSettings.shared.playSound { CaptureFeedback.shutter() }
        RecordingIndicator.show(started: start) { [weak self] in self?.stopRecording() }
    }

    private func failRecording(_ error: Error) {
        recorder = nil
        handle(error)
    }

    /// Each recording gets its own session folder under `Lens Recordings/`, so
    /// the video and its event track (and, later, the Studio render) stay
    /// together instead of scattering loose files across the save folder.
    private func recordingURL() -> URL {
        let folder = (LensSettings.shared.saveFolderPath as NSString).expandingTildeInPath
        let name = OutputWriter.filename(template: LensSettings.shared.filenameTemplate, name: "Lens Recording")
        let session = URL(fileURLWithPath: folder, isDirectory: true)
            .appendingPathComponent("Lens Recordings", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        return session.appendingPathComponent("screen").appendingPathExtension("mp4")
    }

    private func stopRecording() {
        guard let rec = recorder else { return }
        recorder = nil
        recordingStart = nil
        RecordingIndicator.hide()
        let events = tracker?.finish()
        tracker = nil
        let fileURL = recordingFileURL
        recordingFileURL = nil
        let webcam = webcamRecorder
        webcamRecorder = nil
        Task {
            await webcam?.stop()
            let url = (try? await rec.stop()) ?? nil
            // Persist the Studio event track next to the raw video (consumed by
            // the render pass in S2+).
            if let events, let base = url ?? fileURL,
               let data = try? JSONEncoder().encode(events) {
                let sidecar = base.deletingLastPathComponent().appendingPathComponent("events.json")
                try? data.write(to: sidecar)
            }
            if LensSettings.shared.playSound { CaptureFeedback.shutter() }
            if let url {
                let session = url.deletingLastPathComponent().lastPathComponent
                CaptureFeedback.toast("Saved to \(session)")
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
        }
    }

    // MARK: - Capture → compose → route

    /// Run a capture closure on a background task, then finish on the main actor.
    private func runCapture(_ body: @escaping () async throws -> Capture) {
        Task {
            do {
                let capture = try await body()
                self.finish(capture)
            } catch {
                self.handle(error)
            }
        }
    }

    private func finish(_ capture: Capture) {
        if LensSettings.shared.playSound { CaptureFeedback.shutter() }

        let settings = LensSettings.shared
        switch settings.destination {
        case .editor:
            EditorWindowController.present(capture: capture)
        case .tray:
            // Rapid capture: frame to the preset (no backdrop — the collage owns
            // the background) and collect. Don't steal focus; just confirm.
            let framed = Compositor.apply(constraint: capture.preset.constraint, to: capture.image)
            CaptureTray.shared.add(framed, preset: capture.preset)
            CaptureFeedback.toast("Added to tray (\(CaptureTray.shared.count)) — ⌥-click the menu bar to open")
        default:
            let composed = Compositor.compose(
                base: capture.image,
                constraint: capture.preset.constraint,
                backdrop: capture.preset.backdrop ?? .none
            )
            route(composed, to: settings.destination)
        }

        // Don't auto-copy when collecting (rapid capture) or when the clipboard
        // is already the destination.
        if settings.alsoCopyToClipboard, settings.destination != .clipboard, settings.destination != .tray {
            let composed = Compositor.compose(
                base: capture.image,
                constraint: capture.preset.constraint,
                backdrop: capture.preset.backdrop ?? .none
            )
            OutputWriter.copyToClipboard(composed)
        }
        if settings.showThumbnail { CaptureFeedback.flash(capture.image) }
    }

    /// Route a finished, composed image to a non-editor destination.
    func route(_ image: CGImage, to destination: CaptureDestination) {
        let settings = LensSettings.shared
        switch destination {
        case .file:
            do {
                let url = try OutputWriter.write(
                    image, toFolder: settings.saveFolderPath,
                    format: settings.format, quality: settings.quality,
                    template: settings.filenameTemplate
                )
                CaptureFeedback.toast("Saved \(url.lastPathComponent)")
            } catch {
                handle(error)
            }
        case .clipboard:
            OutputWriter.copyToClipboard(image)
            CaptureFeedback.toast("Copied to clipboard")
        case .pin:
            PinWindowController.pin(image)
        case .tray:
            CaptureTray.shared.add(image, preset: settings.activePreset)
            CaptureFeedback.toast("Added to tray (\(CaptureTray.shared.count))")
        case .editor:
            break
        }
    }

    // MARK: - Errors & permission

    private func handle(_ error: Error) {
        // ScreenCaptureKit's permission denial is the common case — turn it into
        // an actionable prompt rather than a cryptic error.
        if !Self.hasScreenRecordingPermission() {
            promptForPermission()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Capture failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func promptForPermission() {
        let alert = NSAlert()
        alert.messageText = "Lens needs Screen Recording access"
        alert.informativeText = "Grant Lens permission in System Settings, then try again."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            _ = CGRequestScreenCaptureAccess()
            Self.openScreenRecordingSettings()
        }
    }

    public static func hasScreenRecordingPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    public static func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }

    // MARK: - Accessibility (global hotkeys + synthetic scroll events)

    /// The global key monitor and scrolling capture both require the process to
    /// be Accessibility-trusted. Surfaced in the About tab and prompted on first
    /// scrolling capture.
    public static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Open the system prompt that adds Lens to the Accessibility list, then
    /// re-arm the hotkey monitor once it's granted.
    public static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            if AXIsProcessTrusted() { GlobalShortcutManager.shared.updateMonitor() }
        }
    }

    private func promptForAccessibility(reason: String) {
        let alert = NSAlert()
        alert.messageText = "Lens needs Accessibility access"
        alert.informativeText = reason
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Self.requestAccessibilityPermission()
        }
    }

    // MARK: - Geometry helpers

    /// Current pointer in global *top-left* CG coordinates (what SCDisplay frames
    /// and ScreenCaptureKit use). `NSEvent.mouseLocation` is bottom-left, so flip
    /// against the primary display height.
    private func globalCGPoint() -> CGPoint {
        let p = NSEvent.mouseLocation
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }

    private func screenUnderMouse() -> NSScreen {
        let loc = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(loc) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}
