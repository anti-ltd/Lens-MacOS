import Foundation
import CoreGraphics

/// One mark on the editor canvas. A flat value type so the editor's undo stack
/// is just an array snapshot, and so a document could be re-rendered headlessly.
/// Coordinates are in the captured image's pixel space (top-left origin).
public struct Annotation: Identifiable, Sendable, Equatable {
    public enum Kind: String, CaseIterable, Sendable, Identifiable {
        case arrow
        case line
        case rectangle
        case ellipse
        case freehand
        case text
        case highlight   // translucent marker fill
        case pixelate    // mosaic the region (hide sensitive info)
        case blur        // gaussian-blur the region
        case spotlight   // dim everything outside the region
        case redact      // solid block-out
        case counter     // numbered step badge

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .arrow:     return "Arrow"
            case .line:      return "Line"
            case .rectangle: return "Rectangle"
            case .ellipse:   return "Ellipse"
            case .freehand:  return "Draw"
            case .text:      return "Text"
            case .highlight: return "Highlight"
            case .pixelate:  return "Pixelate"
            case .blur:      return "Blur"
            case .spotlight: return "Spotlight"
            case .redact:    return "Redact"
            case .counter:   return "Step"
            }
        }

        public var symbol: String {
            switch self {
            case .arrow:     return "arrow.up.right"
            case .line:      return "line.diagonal"
            case .rectangle: return "rectangle"
            case .ellipse:   return "circle"
            case .freehand:  return "scribble"
            case .text:      return "textformat"
            case .highlight: return "highlighter"
            case .pixelate:  return "mosaic"
            case .blur:      return "drop.fill"
            case .spotlight: return "spotlight"
            case .redact:    return "rectangle.fill"
            case .counter:   return "1.circle"
            }
        }

        /// Region tools defined by a bounding box (start→current drag corners).
        public var isRegion: Bool {
            switch self {
            case .rectangle, .ellipse, .highlight, .pixelate, .blur, .spotlight, .redact:
                return true
            case .arrow, .line, .freehand, .text, .counter:
                return false
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    /// Ordered points. Region/segment tools use [start, end]; freehand uses the
    /// full stroke; text/counter use [anchor].
    public var points: [CGPoint]
    public var color: RGBAColor
    public var lineWidth: CGFloat
    public var text: String
    /// For `.counter`, the displayed number.
    public var number: Int
    /// For `.pixelate`, the mosaic block size in pixels.
    public var blockSize: CGFloat

    public init(
        id: UUID = UUID(),
        kind: Kind,
        points: [CGPoint],
        color: RGBAColor = RGBAColor(hex: "#FF3B30")!,
        lineWidth: CGFloat = 4,
        text: String = "",
        number: Int = 1,
        blockSize: CGFloat = 12
    ) {
        self.id = id
        self.kind = kind
        self.points = points
        self.color = color
        self.lineWidth = lineWidth
        self.text = text
        self.number = number
        self.blockSize = blockSize
    }

    /// Bounding box across the annotation's points, inset-padded by line width.
    public var bounds: CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
            .insetBy(dx: -lineWidth, dy: -lineWidth)
    }
}
