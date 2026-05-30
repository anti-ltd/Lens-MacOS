import Foundation

/// Background music mixed under a Studio export. `duck` lowers the music so the
/// recording's own audio sits on top.
public struct MusicTrack: Codable, Sendable, Equatable {
    public var path: String
    public var volume: Double
    public var duck: Bool

    public init(path: String, volume: Double = 0.5, duck: Bool = true) {
        self.path = path
        self.volume = volume
        self.duck = duck
    }

    public var url: URL { URL(fileURLWithPath: path) }
    /// Effective volume after the optional duck.
    public var effectiveVolume: Float { Float(duck ? volume * 0.4 : volume) }
}

/// A full-frame title card shown before (intro) or after (outro) the clip.
public struct TitleCard: Codable, Sendable, Equatable {
    public var title: String
    public var subtitle: String
    public var duration: Double

    public init(title: String, subtitle: String = "", duration: Double = 1.8) {
        self.title = title
        self.subtitle = subtitle
        self.duration = duration
    }
}

/// The per-recording Studio configuration — every framing / camera / cursor /
/// keystroke / webcam knob plus trim and codec. Lives as `studio.json` in the
/// session folder, so an edit is re-openable and the render is reproducible.
/// This is what the S7 editor binds its controls to.
public struct StudioDocument: Codable, Sendable, Equatable {
    public var scene: SceneStyle
    public var camera: CameraStyle
    public var cursor: CursorStyle
    public var keystrokes: KeystrokeStyle
    public var webcam: WebcamStyle
    public var codec: VideoCodec
    /// Trim, in seconds. `trimEnd == nil` (or ≤ start) means "to the end".
    public var trimStart: Double
    public var trimEnd: Double?
    public var music: MusicTrack?
    /// Collapse long idle gaps (no cursor/click/key activity) on export.
    public var removeSilence: Bool
    /// A small corner wordmark shown throughout (logo bug). Empty = off.
    public var watermark: String
    public var intro: TitleCard?
    public var outro: TitleCard?
    public var layers: [StudioLayer]

    public init(
        scene: SceneStyle = StudioPreset.marketing.style,
        camera: CameraStyle = CameraStyle(),
        cursor: CursorStyle = CursorStyle(),
        keystrokes: KeystrokeStyle = KeystrokeStyle(),
        webcam: WebcamStyle = WebcamStyle(),
        codec: VideoCodec = .h264,
        trimStart: Double = 0,
        trimEnd: Double? = nil,
        music: MusicTrack? = nil,
        removeSilence: Bool = false,
        watermark: String = "",
        intro: TitleCard? = nil,
        outro: TitleCard? = nil,
        layers: [StudioLayer] = []
    ) {
        self.scene = scene
        self.camera = camera
        self.cursor = cursor
        self.keystrokes = keystrokes
        self.webcam = webcam
        self.codec = codec
        self.trimStart = trimStart
        self.trimEnd = trimEnd
        self.music = music
        self.removeSilence = removeSilence
        self.watermark = watermark
        self.intro = intro
        self.outro = outro
        self.layers = layers
    }

    // Tolerant decode so documents saved before a field existed still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scene = try c.decodeIfPresent(SceneStyle.self, forKey: .scene) ?? StudioPreset.marketing.style
        camera = try c.decodeIfPresent(CameraStyle.self, forKey: .camera) ?? CameraStyle()
        cursor = try c.decodeIfPresent(CursorStyle.self, forKey: .cursor) ?? CursorStyle()
        keystrokes = try c.decodeIfPresent(KeystrokeStyle.self, forKey: .keystrokes) ?? KeystrokeStyle()
        webcam = try c.decodeIfPresent(WebcamStyle.self, forKey: .webcam) ?? WebcamStyle()
        codec = try c.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? .h264
        trimStart = try c.decodeIfPresent(Double.self, forKey: .trimStart) ?? 0
        trimEnd = try c.decodeIfPresent(Double.self, forKey: .trimEnd)
        music = try c.decodeIfPresent(MusicTrack.self, forKey: .music)
        removeSilence = try c.decodeIfPresent(Bool.self, forKey: .removeSilence) ?? false
        watermark = try c.decodeIfPresent(String.self, forKey: .watermark) ?? ""
        intro = try c.decodeIfPresent(TitleCard.self, forKey: .intro)
        outro = try c.decodeIfPresent(TitleCard.self, forKey: .outro)
        layers = try c.decodeIfPresent([StudioLayer].self, forKey: .layers) ?? []
    }

    public static let fileName = "studio.json"

    /// Load `studio.json` from a session folder, or nil if absent/garbled.
    public static func load(from folder: URL) -> StudioDocument? {
        let url = folder.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StudioDocument.self, from: data)
    }

    /// Persist to the session folder.
    public func save(to folder: URL) {
        let url = folder.appendingPathComponent(Self.fileName)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url) }
    }
}
