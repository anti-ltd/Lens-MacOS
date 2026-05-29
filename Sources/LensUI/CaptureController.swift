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

    // MARK: - Entry

    public func perform(_ mode: CaptureMode) {
        let preset = LensSettings.shared.activePreset
        switch mode {
        case .fullScreen:  captureFullScreen(preset: preset)
        case .area:        captureArea(preset: preset)
        case .window:      captureWindow(preset: preset)
        case .scrolling:   captureScrolling(preset: preset)
        case .colorPicker: pickColor()
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
        default:
            let composed = Compositor.compose(
                base: capture.image,
                constraint: capture.preset.constraint,
                backdrop: capture.preset.backdrop ?? .none
            )
            route(composed, to: settings.destination)
        }

        if settings.alsoCopyToClipboard, settings.destination != .clipboard {
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
