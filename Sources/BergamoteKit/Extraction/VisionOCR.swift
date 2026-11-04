import CoreGraphics
import Vision

/// OCR natif d'Apple (Vision), hors ligne, sans modèle à livrer.
public struct VisionOCR: Sendable {
    public var languages = ["fr-FR", "en-US"]
    public var usesLanguageCorrection = true

    public init() {}

    /// Lignes reconnues, de haut en bas puis de gauche à droite.
    public func recognize(_ image: CGImage) throws -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = usesLanguageCorrection
        try VNImageRequestHandler(cgImage: image).perform([request])
        // Les rectangles de Vision ont leur origine en bas à gauche : y décroissant = lecture vers le bas.
        let observations = (request.results ?? []).sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}
