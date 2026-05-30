import Foundation
import Combine

/// User-tunable settings, persisted to `UserDefaults` and observed by SwiftUI.
///
/// Each property writes through to `UserDefaults` on `didSet`, so flipping a
/// setting from anywhere (the popover, code, defaults write) takes effect
/// immediately for every observer. Mirrors FileMaster's settings shape.
public final class LensSettings: ObservableObject {
    public static let shared = LensSettings()

    /// The backing store. Normally `.standard`; under appstage capture (which
    /// sets `LENS_STATE_DIR`) it's an isolated suite so seeding demo state never
    /// touches the user's real preferences.
    static let defaults: UserDefaults = {
        if let dir = ProcessInfo.processInfo.environment["LENS_STATE_DIR"], !dir.isEmpty {
            return UserDefaults(suiteName: "ltd.anti.lens.capture") ?? .standard
        }
        return .standard
    }()

    // MARK: - Presets

    /// The user's preset library (built-ins seeded on first launch). Encoded as
    /// JSON in one defaults key so reordering/renaming round-trips atomically.
    @Published public var presets: [Preset] {
        didSet { Self.encode(presets, forKey: "presets") }
    }

    /// Which preset drives the next capture's frame constraint + default backdrop.
    @Published public var activePresetID: UUID? {
        didSet { Self.defaults.set(activePresetID?.uuidString, forKey: "activePresetID") }
    }

    public var activePreset: Preset {
        presets.first { $0.id == activePresetID } ?? presets.first ?? Preset(name: "Free", constraint: .free)
    }

    // MARK: - Output

    @Published public var format: OutputFormat {
        didSet { Self.defaults.set(format.rawValue, forKey: "format") }
    }

    /// JPEG/HEIC quality, 0...1. Ignored for lossless formats.
    @Published public var quality: Double {
        didSet { Self.defaults.set(quality, forKey: "quality") }
    }

    /// What happens to a finished capture by default.
    @Published public var destination: CaptureDestination {
        didSet { Self.defaults.set(destination.rawValue, forKey: "destination") }
    }

    /// Folder captures are written to (when destination is `.file`, or when the
    /// editor saves). Defaults to ~/Desktop, matching the OS screenshot default.
    @Published public var saveFolderPath: String {
        didSet { Self.defaults.set(saveFolderPath, forKey: "saveFolderPath") }
    }

    /// strftime-ish filename template. Tokens: {name} {date} {time} {seq}.
    @Published public var filenameTemplate: String {
        didSet { Self.defaults.set(filenameTemplate, forKey: "filenameTemplate") }
    }

    /// Always copy to the clipboard in addition to the chosen destination.
    @Published public var alsoCopyToClipboard: Bool {
        didSet { Self.defaults.set(alsoCopyToClipboard, forKey: "alsoCopyToClipboard") }
    }

    // MARK: - Capture behaviour

    /// Include the mouse cursor in captures.
    @Published public var captureCursor: Bool {
        didSet { Self.defaults.set(captureCursor, forKey: "captureCursor") }
    }

    /// Include the window's drop shadow in window captures.
    @Published public var windowShadow: Bool {
        didSet { Self.defaults.set(windowShadow, forKey: "windowShadow") }
    }

    /// Play the shutter sound on capture.
    @Published public var playSound: Bool {
        didSet { Self.defaults.set(playSound, forKey: "playSound") }
    }

    /// Show a brief flash/thumbnail confirmation after capture.
    @Published public var showThumbnail: Bool {
        didSet { Self.defaults.set(showThumbnail, forKey: "showThumbnail") }
    }

    // MARK: - Recording

    /// What a screen recording captures (full screen / region / window).
    @Published public var recordingSource: RecordingSource {
        didSet { Self.defaults.set(recordingSource.rawValue, forKey: "recordingSource") }
    }

    /// Recording frame rate.
    @Published public var recordingFPS: RecordingFPS {
        didSet { Self.defaults.set(recordingFPS.rawValue, forKey: "recordingFPS") }
    }

    /// Recording video codec (H.264 / HEVC).
    @Published public var recordingCodec: VideoCodec {
        didSet { Self.defaults.set(recordingCodec.rawValue, forKey: "recordingCodec") }
    }

    /// Include the cursor in recordings (independent of the screenshot setting —
    /// in a recording the cursor is usually the star).
    @Published public var recordCursor: Bool {
        didSet { Self.defaults.set(recordCursor, forKey: "recordCursor") }
    }

    /// The scene preset the Studio render applies (framing / background / chrome).
    @Published public var studioPreset: StudioPreset {
        didSet { Self.defaults.set(studioPreset.rawValue, forKey: "studioPreset") }
    }

    /// Auto-zoom (the cinematic camera that follows clicks) on Studio renders.
    @Published public var studioAutoZoom: Bool {
        didSet { Self.defaults.set(studioAutoZoom, forKey: "studioAutoZoom") }
    }

    /// Auto-zoom target scale (1 = none).
    @Published public var studioZoom: Double {
        didSet { Self.defaults.set(studioZoom, forKey: "studioZoom") }
    }

    /// Punchy ("pop") zoom easing instead of the smooth ease.
    @Published public var studioPunchyZoom: Bool {
        didSet { Self.defaults.set(studioPunchyZoom, forKey: "studioPunchyZoom") }
    }

    /// The camera tuning derived from the settings above.
    public var cameraStyle: CameraStyle {
        CameraStyle(enabled: studioAutoZoom, zoom: CGFloat(studioZoom),
                    easing: studioPunchyZoom ? .punchy : .smooth)
    }

    /// Cinematic cursor (synthetic, enlarged) on Studio renders.
    @Published public var studioCursor: Bool {
        didSet { Self.defaults.set(studioCursor, forKey: "studioCursor") }
    }

    /// Cinematic cursor size multiplier.
    @Published public var studioCursorSize: Double {
        didSet { Self.defaults.set(studioCursorSize, forKey: "studioCursorSize") }
    }

    /// Click ripples on Studio renders.
    @Published public var studioClickRipples: Bool {
        didSet { Self.defaults.set(studioClickRipples, forKey: "studioClickRipples") }
    }

    /// Spotlight dim around the cursor (0 = off).
    @Published public var studioSpotlight: Double {
        didSet { Self.defaults.set(studioSpotlight, forKey: "studioSpotlight") }
    }

    public var cursorStyle: CursorStyle {
        CursorStyle(enabled: studioCursor, size: CGFloat(studioCursorSize),
                    clickRipples: studioClickRipples, spotlight: studioSpotlight)
    }

    /// Keystroke overlay (shortcut captions) on Studio renders.
    @Published public var studioKeystrokes: Bool {
        didSet { Self.defaults.set(studioKeystrokes, forKey: "studioKeystrokes") }
    }

    public var keystrokeStyle: KeystrokeStyle {
        KeystrokeStyle(enabled: studioKeystrokes)
    }

    /// Webcam picture-in-picture on Studio renders (records `camera.mov`).
    @Published public var studioWebcam: Bool {
        didSet { Self.defaults.set(studioWebcam, forKey: "studioWebcam") }
    }
    @Published public var studioWebcamSize: Double {
        didSet { Self.defaults.set(studioWebcamSize, forKey: "studioWebcamSize") }
    }
    @Published public var studioWebcamCorner: WebcamStyle.Corner {
        didSet { Self.defaults.set(studioWebcamCorner.rawValue, forKey: "studioWebcamCorner") }
    }

    public var webcamStyle: WebcamStyle {
        WebcamStyle(enabled: studioWebcam, sizeFraction: CGFloat(studioWebcamSize), corner: studioWebcamCorner)
    }

    /// Mix system audio into the recording (macOS 13+).
    @Published public var recordSystemAudio: Bool {
        didSet { Self.defaults.set(recordSystemAudio, forKey: "recordSystemAudio") }
    }

    /// Mix the microphone into the recording (macOS 15+; ignored on older macOS).
    @Published public var recordMicrophone: Bool {
        didSet { Self.defaults.set(recordMicrophone, forKey: "recordMicrophone") }
    }

    // MARK: - Hotkeys

    /// Per-mode global hotkeys, keyed by `CaptureMode.rawValue`. JSON-encoded.
    @Published public var hotkeys: [String: HotkeyBinding] {
        didSet { Self.encode(hotkeys, forKey: "hotkeys") }
    }

    public func binding(for mode: CaptureMode) -> HotkeyBinding {
        hotkeys[mode.rawValue] ?? .unbound
    }

    public func setBinding(_ binding: HotkeyBinding, for mode: CaptureMode) {
        hotkeys[mode.rawValue] = binding
    }

    // MARK: - Init

    private init() {
        let d = Self.defaults

        let loadedPresets: [Preset]
        if let decoded: [Preset] = Self.decode([Preset].self, forKey: "presets"), !decoded.isEmpty {
            loadedPresets = decoded
        } else {
            loadedPresets = Preset.builtins
        }
        presets = loadedPresets
        if let raw = d.string(forKey: "activePresetID") {
            activePresetID = UUID(uuidString: raw)
        } else {
            activePresetID = loadedPresets.first?.id
        }

        format = OutputFormat(rawValue: d.string(forKey: "format") ?? "") ?? .png
        quality = d.object(forKey: "quality") as? Double ?? 0.9
        destination = CaptureDestination(rawValue: d.string(forKey: "destination") ?? "") ?? .editor
        saveFolderPath = d.string(forKey: "saveFolderPath")
            ?? (NSHomeDirectory() as NSString).appendingPathComponent("Desktop")
        filenameTemplate = d.string(forKey: "filenameTemplate") ?? "Lens {date} {time}"
        alsoCopyToClipboard = d.object(forKey: "alsoCopyToClipboard") as? Bool ?? true
        captureCursor = d.bool(forKey: "captureCursor")
        windowShadow = d.object(forKey: "windowShadow") as? Bool ?? true
        playSound = d.object(forKey: "playSound") as? Bool ?? true
        showThumbnail = d.object(forKey: "showThumbnail") as? Bool ?? true

        recordingSource = RecordingSource(rawValue: d.string(forKey: "recordingSource") ?? "") ?? .fullScreen
        recordingFPS = RecordingFPS(rawValue: d.object(forKey: "recordingFPS") as? Int ?? 0) ?? .fps60
        recordingCodec = VideoCodec(rawValue: d.string(forKey: "recordingCodec") ?? "") ?? .h264
        recordCursor = d.object(forKey: "recordCursor") as? Bool ?? true
        studioPreset = StudioPreset(rawValue: d.string(forKey: "studioPreset") ?? "") ?? .marketing
        studioAutoZoom = d.object(forKey: "studioAutoZoom") as? Bool ?? true
        studioZoom = d.object(forKey: "studioZoom") as? Double ?? 2.0
        studioPunchyZoom = d.object(forKey: "studioPunchyZoom") as? Bool ?? false
        studioCursor = d.object(forKey: "studioCursor") as? Bool ?? false
        studioCursorSize = d.object(forKey: "studioCursorSize") as? Double ?? 1.5
        studioClickRipples = d.object(forKey: "studioClickRipples") as? Bool ?? true
        studioSpotlight = d.object(forKey: "studioSpotlight") as? Double ?? 0
        studioKeystrokes = d.object(forKey: "studioKeystrokes") as? Bool ?? false
        studioWebcam = d.object(forKey: "studioWebcam") as? Bool ?? false
        studioWebcamSize = d.object(forKey: "studioWebcamSize") as? Double ?? 0.24
        studioWebcamCorner = WebcamStyle.Corner(rawValue: d.string(forKey: "studioWebcamCorner") ?? "") ?? .bottomRight
        recordSystemAudio = d.bool(forKey: "recordSystemAudio")
        recordMicrophone = d.bool(forKey: "recordMicrophone")

        hotkeys = Self.decode([String: HotkeyBinding].self, forKey: "hotkeys") ?? Self.defaultHotkeys
    }

    /// Sensible starting hotkeys that don't collide with the macOS defaults
    /// (⌘⇧3/4/5). We layer on ⌃ to stay clear.
    private static let defaultHotkeys: [String: HotkeyBinding] = {
        let ctrlShiftCmd = (1 << 18) | (1 << 17) | (1 << 20)
        return [
            CaptureMode.area.rawValue:        HotkeyBinding(keyCode: 21, modifiers: ctrlShiftCmd), // 4
            CaptureMode.window.rawValue:      HotkeyBinding(keyCode: 23, modifiers: ctrlShiftCmd), // 5
            CaptureMode.fullScreen.rawValue:  HotkeyBinding(keyCode: 20, modifiers: ctrlShiftCmd), // 3
            CaptureMode.scrolling.rawValue:   HotkeyBinding(keyCode: 22, modifiers: ctrlShiftCmd), // 6
            CaptureMode.colorPicker.rawValue: HotkeyBinding(keyCode: 7,  modifiers: ctrlShiftCmd), // X
            CaptureMode.video.rawValue:       HotkeyBinding(keyCode: 9,  modifiers: ctrlShiftCmd), // V
        ]
    }()

    // MARK: - JSON helpers

    private static func encode<T: Encodable>(_ value: T, forKey key: String) {
        if let data = try? JSONEncoder().encode(value) {
            Self.defaults.set(data, forKey: key)
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = Self.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
