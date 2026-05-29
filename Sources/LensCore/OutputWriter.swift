import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Encodes finished captures and gets them where they're going: a file in the
/// configured folder, the clipboard, or both. Filename templating lives here so
/// the "unclutter your desktop" dedicated-folder workflow is one setting.
public enum OutputWriter {

    private static var sequence = 0

    /// Encode a `CGImage` to the given format's data, honouring lossy quality.
    public static func encode(_ image: CGImage, format: OutputFormat, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            data, format.utType.identifier as CFString, 1, nil
        ) else { return nil }
        var props: [CFString: Any] = [:]
        if format.isLossy {
            props[kCGImageDestinationLossyCompressionQuality] = quality
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }

    /// Resolve the configured template into a base filename (no extension).
    /// Tokens: `{name}` `{date}` `{time}` `{seq}`.
    public static func filename(template: String, name: String = "Lens") -> String {
        sequence += 1
        let now = Date()
        let date = DateFormatter(); date.dateFormat = "yyyy-MM-dd"
        let time = DateFormatter(); time.dateFormat = "HH.mm.ss"
        var s = template
        s = s.replacingOccurrences(of: "{name}", with: name)
        s = s.replacingOccurrences(of: "{date}", with: date.string(from: now))
        s = s.replacingOccurrences(of: "{time}", with: time.string(from: now))
        s = s.replacingOccurrences(of: "{seq}", with: String(format: "%03d", sequence))
        // Strip path separators a careless template might introduce.
        s = s.replacingOccurrences(of: "/", with: "-")
        return s.isEmpty ? "Lens" : s
    }

    /// Write `image` into `folder` using the template. Returns the written URL.
    @discardableResult
    public static func write(
        _ image: CGImage,
        toFolder folder: String,
        format: OutputFormat,
        quality: Double,
        template: String
    ) throws -> URL {
        guard let data = encode(image, format: format, quality: quality) else {
            throw WriteError.encodeFailed
        }
        let dir = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var url = dir.appendingPathComponent(filename(template: template))
            .appendingPathExtension(format.fileExtension)
        // Avoid clobbering an identical name within the same second.
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            let base = dir.appendingPathComponent(filename(template: template) + " \(n)")
            url = base.appendingPathExtension(format.fileExtension)
            n += 1
        }
        try data.write(to: url)
        return url
    }

    /// Put the image on the general pasteboard as both TIFF and PNG.
    public static func copyToClipboard(_ image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
        if let tiff = rep.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    /// Put plain text (OCR result, hex colour) on the pasteboard.
    public static func copyToClipboard(text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    public enum WriteError: Error, LocalizedError {
        case encodeFailed
        public var errorDescription: String? { "Could not encode the image." }
    }
}
