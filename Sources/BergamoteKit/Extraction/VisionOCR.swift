import CoreGraphics
import Vision

/// OCR natif d'Apple (Vision), hors ligne, sans modèle à livrer.
public struct VisionOCR: Sendable {
    public var languages = ["fr-FR", "en-US"]
    public var usesLanguageCorrection = true

    public init() {}

    /// Une ligne reconnue = un bloc. Les rectangles de Vision sont déjà normalisés, origine en
    /// bas à gauche : le même repère que les pages PDF.
    public func recognize(_ image: CGImage) throws -> [TextBlock] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = usesLanguageCorrection
        try VNImageRequestHandler(cgImage: image).perform([request])
        let observations = (request.results ?? []).sorted {
            // Lecture de haut en bas, puis de gauche à droite.
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return TextBlock(text: candidate.string, bbox: NormalizedRect(observation.boundingBox))
        }
    }
}
