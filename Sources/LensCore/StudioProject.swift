import Foundation

/// One clip on a Studio project's timeline: a recording session plus the
/// `StudioDocument` that styles it. Clips play back-to-back in array order
/// (single track for now; the model leaves room for layered tracks in S10).
public struct StudioClip: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    /// Absolute path to the recording session folder (holds `screen.mp4`).
    public var sessionPath: String
    public var document: StudioDocument
    public var enabled: Bool

    public init(id: UUID = UUID(), name: String, sessionPath: String,
                document: StudioDocument = StudioDocument(), enabled: Bool = true) {
        self.id = id
        self.name = name
        self.sessionPath = sessionPath
        self.document = document
        self.enabled = enabled
    }

    public var sessionURL: URL { URL(fileURLWithPath: sessionPath, isDirectory: true) }
}

/// A multi-clip Studio project — the "build a video from several recordings"
/// document. Saved as a `.lensproj` JSON file that references session folders.
public struct StudioProject: Codable, Sendable, Equatable {
    public var name: String
    public var clips: [StudioClip]
    /// Cross-dissolve duration between clips (seconds). 0 = hard cuts.
    public var transition: Double

    public init(name: String = "Untitled", clips: [StudioClip] = [], transition: Double = 0) {
        self.name = name
        self.clips = clips
        self.transition = transition
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        clips = try c.decodeIfPresent([StudioClip].self, forKey: .clips) ?? []
        transition = try c.decodeIfPresent(Double.self, forKey: .transition) ?? 0
    }

    public static let fileExtension = "lensproj"

    public var enabledClips: [StudioClip] { clips.filter(\.enabled) }

    public static func load(from url: URL) -> StudioProject? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(StudioProject.self, from: data)
    }

    public func save(to url: URL) throws {
        let data = try JSONEncoder().encode(self)
        try data.write(to: url)
    }
}
