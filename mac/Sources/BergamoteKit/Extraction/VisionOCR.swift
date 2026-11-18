import CoreGraphics
import Vision

/// OCR natif d'Apple (Vision), hors ligne, sans modèle à livrer.
public struct VisionOCR: Sendable {
    public var languages = ["fr-FR", "en-US"]
    public var usesLanguageCorrection = true

    public init() {}

    /// Une ligne reconnue et son cadre, en fraction de l'image, origine en bas à gauche.
    public struct Line: Sendable {
        public let text: String
        public let box: CGRect
    }

    /// Lignes reconnues, de haut en bas puis de gauche à droite.
    public func recognize(_ image: CGImage) throws -> [String] {
        try lines(in: image).map(\.text)
    }

    private static func request(level: VNRequestTextRecognitionLevel, languages: [String], correction: Bool) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = correction
        return request
    }

    /// Lignes reconnues avec leur position, de haut en bas puis de gauche à droite.
    public func lines(in image: CGImage) throws -> [Line] {
        // Le mode précis s'appuie sur un modèle que macOS prépare à la demande ; il arrive que le
        // système n'y parvienne pas. Le mode rapide, lui, répond toujours : mieux vaut son texte
        // qu'une erreur.
        var request = Self.request(level: .accurate, languages: languages, correction: usesLanguageCorrection)
        do {
            try VNImageRequestHandler(cgImage: image).perform([request])
        } catch {
            request = Self.request(level: .fast, languages: languages, correction: usesLanguageCorrection)
            try VNImageRequestHandler(cgImage: image).perform([request])
        }
        // Les rectangles de Vision ont leur origine en bas à gauche : y décroissant = lecture vers le bas.
        let observations = (request.results ?? []).sorted {
            abs($0.boundingBox.midY - $1.boundingBox.midY) > 0.01
                ? $0.boundingBox.midY > $1.boundingBox.midY
                : $0.boundingBox.minX < $1.boundingBox.minX
        }
        return observations.compactMap { observation in
            observation.topCandidates(1).first.map { Line(text: $0.string, box: observation.boundingBox) }
        }
    }
}
