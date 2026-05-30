import CoreGraphics
import Foundation

/// Lays a set of captures out into a single grid image — the "group them into a
/// collage" half of rapid capture. Each image is aspect-fit into a uniform cell
/// so mixed sizes line up; spacing, padding, background and rounded tiles are
/// all configurable. Pure Core Graphics, so it stays UI-free and testable.
public enum CollageComposer {

    public struct Options: Sendable {
        /// Fixed column count, or 0 to auto-pick a near-square grid.
        public var columns: Int
        /// Gap between tiles, in pixels.
        public var spacing: CGFloat
        /// Outer margin around the grid.
        public var padding: CGFloat
        /// Longest side of a tile; images are scaled to fit a cell this big.
        public var maxTile: CGFloat
        public var background: Backdrop.Fill
        public var cornerRadius: CGFloat

        public init(
            columns: Int = 0,
            spacing: CGFloat = 16,
            padding: CGFloat = 24,
            maxTile: CGFloat = 480,
            background: Backdrop.Fill = .solid(RGBAColor(hex: "#0D1326")!),
            cornerRadius: CGFloat = 10
        ) {
            self.columns = columns
            self.spacing = spacing
            self.padding = padding
            self.maxTile = maxTile
            self.background = background
            self.cornerRadius = cornerRadius
        }
    }

    /// Auto-pick a near-square column count for `n` images.
    public static func autoColumns(_ n: Int) -> Int {
        guard n > 1 else { return 1 }
        return Int(Double(n).squareRoot().rounded(.up))
    }

    /// Compose `images` into one grid image. Returns nil if `images` is empty or
    /// a drawing context can't be made.
    public static func make(_ images: [CGImage], options: Options = Options()) -> CGImage? {
        guard !images.isEmpty else { return nil }
        let n = images.count
        let cols = options.columns > 0 ? min(options.columns, n) : autoColumns(n)
        let rows = Int((Double(n) / Double(cols)).rounded(.up))

        // Uniform square cells keep mixed aspect ratios aligned.
        let cell = options.maxTile
        let canvasW = options.padding * 2 + CGFloat(cols) * cell + CGFloat(cols - 1) * options.spacing
        let canvasH = options.padding * 2 + CGFloat(rows) * cell + CGFloat(rows - 1) * options.spacing
        let w = Int(canvasW.rounded()), h = Int(canvasH.rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        let full = CGRect(x: 0, y: 0, width: w, height: h)
        fill(options.background, in: ctx, rect: full)

        for (i, image) in images.enumerated() {
            let col = i % cols, row = i / cols
            // Cell origin in top-left space.
            let cellX = options.padding + CGFloat(col) * (cell + options.spacing)
            let cellTop = options.padding + CGFloat(row) * (cell + options.spacing)
            let fit = aspectFit(CGSize(width: image.width, height: image.height),
                                into: CGSize(width: cell, height: cell))
            // Centre within the cell, convert top-left → bottom-left for CG.
            let x = cellX + (cell - fit.width) / 2
            let topY = cellTop + (cell - fit.height) / 2
            let rect = CGRect(x: x, y: canvasH - topY - fit.height, width: fit.width, height: fit.height)

            ctx.saveGState()
            if options.cornerRadius > 0 {
                ctx.addPath(CGPath(roundedRect: rect, cornerWidth: options.cornerRadius,
                                   cornerHeight: options.cornerRadius, transform: nil))
                ctx.clip()
            }
            ctx.draw(image, in: rect)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    // MARK: - Helpers

    private static func aspectFit(_ size: CGSize, into box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private static func fill(_ fill: Backdrop.Fill, in ctx: CGContext, rect: CGRect) {
        switch fill {
        case .transparent:
            break
        case let .solid(c):
            ctx.setFillColor(c.cgColor); ctx.fill(rect)
        case let .gradient(from, to):
            let space = CGColorSpace(name: CGColorSpace.sRGB)!
            if let g = CGGradient(colorsSpace: space,
                                  colors: [from.cgColor, to.cgColor] as CFArray, locations: [0, 1]) {
                ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: rect.height),
                                       end: CGPoint(x: rect.width, y: 0), options: [])
            }
        }
    }
}
