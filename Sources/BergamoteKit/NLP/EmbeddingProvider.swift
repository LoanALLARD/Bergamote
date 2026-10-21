import Accelerate
import Foundation

public enum EmbeddingInput: Sendable {
    case query
    case passage
}

/// Un modèle d'embedding de phrases. Les vecteurs renvoyés sont normalisés (norme L2 = 1) :
/// la distance L2 de sqlite-vec classe alors exactement comme la similarité cosinus.
public protocol EmbeddingProvider: Sendable {
    /// Identifiant stable : s'il change, l'index vectoriel est reconstruit.
    var modelID: String { get }
    var dimension: Int { get }
    /// `false` pour un embedding lexical : la recherche n'affiche alors pas de résultats « par sens ».
    var isSemantic: Bool { get }
    func embed(_ texts: [String], as input: EmbeddingInput) async throws -> [[Float]]
}

extension EmbeddingProvider {
    public var isSemantic: Bool { true }
}

public enum Embeddings {
    public static func normalized(_ vector: [Float]) -> [Float] {
        var norm: Float = 0
        vDSP_svesq(vector, 1, &norm, vDSP_Length(vector.count))
        norm = norm.squareRoot()
        return norm > 0 ? vector.map { $0 / norm } : vector
    }

    public static func dot(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count, "dimensions différentes")
        var result: Float = 0
        vDSP_dotpr(a, 1, b, 1, &result, vDSP_Length(a.count))
        return result
    }

    /// Moyenne normalisée, ou `nil` si la liste est vide.
    public static func mean(_ vectors: [[Float]]) -> [Float]? {
        guard let first = vectors.first else { return nil }
        var sum = [Float](repeating: 0, count: first.count)
        for vector in vectors { vDSP_vadd(sum, 1, vector, 1, &sum, 1, vDSP_Length(sum.count)) }
        return normalized(sum)
    }

    /// Format attendu par sqlite-vec : float32 petit-boutiste contigus.
    public static func blob(_ vector: [Float]) -> Data {
        vector.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    public static func vector(from data: Data) -> [Float] {
        var vector = [Float](repeating: 0, count: data.count / MemoryLayout<Float>.stride)
        _ = vector.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return vector
    }
}

public enum EmbeddingError: Error, LocalizedError {
    case unavailable(String)
    case missingOutput(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let detail): "Modèle d'embedding indisponible : \(detail)"
        case .missingOutput(let name): "Sortie « \(name) » absente du modèle Core ML"
        }
    }
}

/// Embedding « sac de lemmes » haché, déterministe. C'est le repli tant qu'aucun modèle
/// CamemBERT Core ML n'est installé : il ne fait pas de recherche par le sens, mais il suffit
/// au classement par mots-clés et aux documents similaires.
///
/// Les embeddings de phrases de macOS (`NLEmbedding.sentenceEmbedding(for: .french)`) ont été
/// écartés : sur le jeu d'essai, le bon document n'arrive premier que pour 1 requête sur 7.
public struct HashingEmbedder: EmbeddingProvider {
    public let dimension: Int
    public var modelID: String { "hashing-\(dimension)" }
    public var isSemantic: Bool { false }
    private let normalizer = FrenchNormalizer()

    public init(dimension: Int = 256) {
        self.dimension = dimension
    }

    public func embed(_ texts: [String], as input: EmbeddingInput) async throws -> [[Float]] {
        texts.map { text in
            var vector = [Float](repeating: 0, count: dimension)
            for term in normalizer.terms(text) {
                vector[Int(Self.fnv1a(term) % UInt64(dimension))] += 1
            }
            return Embeddings.normalized(vector)
        }
    }

    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return hash
    }
}
