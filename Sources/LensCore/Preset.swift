import Foundation
import CoreGraphics

/// How a capture's frame is constrained. This is the heart of Lens's
/// "repeatable" half — set a ratio or exact pixel size once and every capture
/// comes out matching, no editor round-trip.
public enum FrameConstraint: Codable, Sendable, Equatable {
    /// No constraint — freehand selection, capture exactly what's dragged.
    case free
    /// Lock the aspect ratio (e.g. 16:9). The selection rectangle is forced to
    /// this ratio while dragging; window/full-screen grabs are centre-cropped.
    case ratio(w: Double, h: Double)
    /// Lock to exact output pixels (e.g. 1920×1080). The capture is resized to
    /// land at precisely this size after grabbing.
    case pixels(w: Int, h: Int)

    /// The ratio implied by this constraint, if any (pixels imply one too).
    public var aspect: CGFloat? {
        switch self {
        case .free: return nil
        case let .ratio(w, h): return h == 0 ? nil : CGFloat(w / h)
        case let .pixels(w, h): return h == 0 ? nil : CGFloat(Double(w) / Double(h))
        }
    }

    /// Compact label for chips and read-outs ("16:9", "1920×1080", "Free").
    public var label: String {
        switch self {
        case .free: return "Free"
        case let .ratio(w, h): return "\(trimmed(w)):\(trimmed(h))"
        case let .pixels(w, h): return "\(w)×\(h)"
        }
    }

    private func trimmed(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(v)
    }
}

/// A named, reusable capture configuration. The "presets for every context"
/// answer — documentation, social, ads — switchable in one click, synced via
/// the settings store.
public struct Preset: Codable, Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var constraint: FrameConstraint
    /// Optional backdrop applied automatically when this preset is active.
    public var backdrop: Backdrop?

    public init(
        id: UUID = UUID(),
        name: String,
        constraint: FrameConstraint,
        backdrop: Backdrop? = nil
    ) {
        self.id = id
        self.name = name
        self.constraint = constraint
        self.backdrop = backdrop
    }
}

public extension Preset {
    /// The shipped starter set, covering the contexts the competitors' presets
    /// do (docs, social, ads) plus a freehand default.
    static let builtins: [Preset] = [
        Preset(name: "Free",        constraint: .free),
        Preset(name: "Square",      constraint: .ratio(w: 1, h: 1)),
        Preset(name: "16:9",        constraint: .ratio(w: 16, h: 9)),
        Preset(name: "4:3",         constraint: .ratio(w: 4, h: 3)),
        Preset(name: "Full HD",     constraint: .pixels(w: 1920, h: 1080)),
        Preset(name: "Open Graph",  constraint: .pixels(w: 1200, h: 630)),
        Preset(name: "Stories",     constraint: .ratio(w: 9, h: 16)),
        Preset(name: "Mac App Store", constraint: .pixels(w: 1280, h: 800)),
    ]
}
