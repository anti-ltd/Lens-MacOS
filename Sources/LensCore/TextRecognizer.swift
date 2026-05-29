import Foundation
import Vision
import CoreGraphics

/// On-device OCR (and QR/barcode reading) over a captured image, via Vision.
/// Beats the "came by a text that won't select?" workflow — select a region,
/// get the text on the clipboard, no network.
public enum TextRecognizer {

    /// Recognise text in the image, returning the joined lines (top-to-bottom).
    /// Runs the accurate path with language correction.
    public static func recognizeText(in image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let lines = (request.results ?? []).compactMap { obs in
            obs.topCandidates(1).first?.string
        }
        return lines.joined(separator: "\n")
    }

    /// Decode any QR codes / barcodes present, returning their payload strings.
    public static func readCodes(in image: CGImage) throws -> [String] {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return (request.results ?? []).compactMap { $0.payloadStringValue }
    }
}
