import Foundation
import CoreGraphics
@preconcurrency import ScreenCaptureKit

/// The pixel grabber. Wraps ScreenCaptureKit's modern, permission-gated capture
/// path (`SCScreenshotManager`, macOS 14+) so the UI layer only ever deals in
/// `CGImage`s. Display/window enumeration, retina-correct sizing, and optional
/// cropping all live here.
@available(macOS 14.0, *)
public enum CaptureEngine {

    public enum CaptureError: Error, LocalizedError {
        case noDisplay
        case noContent
        case cropOutOfBounds

        public var errorDescription: String? {
            switch self {
            case .noDisplay:       return "No display available to capture."
            case .noContent:       return "Screen capture content was unavailable."
            case .cropOutOfBounds: return "The selection fell outside the captured image."
            }
        }
    }

    /// Everything currently capturable: on-screen windows and displays. Throws
    /// `SCStream`'s permission error if Screen Recording hasn't been granted —
    /// the caller turns that into a "grant access" prompt.
    public static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    /// Pixel scale for a display (2 on retina, 1 otherwise).
    public static func scale(for display: SCDisplay) -> CGFloat {
        guard let mode = CGDisplayCopyDisplayMode(display.displayID), mode.width > 0 else { return 2 }
        return CGFloat(mode.pixelWidth) / CGFloat(mode.width)
    }

    /// Capture a whole display. Pass `cropPixels` (in the display's *pixel*
    /// space, top-left origin) to grab just a region — that's the area-capture
    /// path: snap the full display, then crop, which keeps the selection crisp
    /// and lets the overlay live entirely in the UI layer.
    public static func captureDisplay(
        _ display: SCDisplay,
        showCursor: Bool,
        cropPixels: CGRect? = nil
    ) async throws -> CGImage {
        let s = scale(for: display)
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * s)
        config.height = Int(CGFloat(display.height) * s)
        config.showsCursor = showCursor
        config.captureResolution = .best
        config.scalesToFit = false

        let full = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let crop = cropPixels else { return full }
        let bounds = CGRect(x: 0, y: 0, width: full.width, height: full.height)
        let r = crop.integral.intersection(bounds)
        guard !r.isNull, r.width >= 1, r.height >= 1, let cut = full.cropping(to: r) else {
            throw CaptureError.cropOutOfBounds
        }
        return cut
    }

    /// Capture a single window, optionally including its drop shadow. ScreenshotKit
    /// captures the window content tightly; the shadow is added in the compositor
    /// when requested so we never bake the desktop behind it.
    public static func captureWindow(
        _ window: SCWindow,
        showCursor: Bool,
        scale: CGFloat = 2
    ) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.showsCursor = showCursor
        config.captureResolution = .best
        config.ignoreShadowsSingleWindow = true
        config.scalesToFit = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    /// The display whose frame contains `point` (global, top-left CG coords),
    /// or the first display as a fallback.
    public static func display(containing point: CGPoint, in content: SCShareableContent) -> SCDisplay? {
        content.displays.first { $0.frame.contains(point) } ?? content.displays.first
    }
}
