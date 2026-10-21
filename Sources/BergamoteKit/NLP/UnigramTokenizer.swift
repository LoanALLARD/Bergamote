import Foundation

public enum TokenizerError: Error, LocalizedError {
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let detail): "tokenizer.json non pris en charge : \(detail)"
        }
    }
}

/// Tokenizer Unigram (SentencePiece) qui lit un `tokenizer.json` Hugging Face, sans dépendance.
///
/// Il couvre ce dont CamemBERT a besoin : normalisation NFKC, pré-tokenisation Metaspace (« ▁ »),
/// découpage de Viterbi, jetons spéciaux `<s> … </s>`. La normalisation « precompiled » de
/// SentencePiece est approchée par NFKC : `scripts/convert_camembert.py` produit un jeu de
/// référence pour vérifier la parité avec la bibliothèque Python (voir les tests).
public struct UnigramTokenizer: Sendable {
    public let bosID: Int
    public let eosID: Int
    public let padID: Int
    public let unkID: Int
    private let vocab: [String: Piece]
    private let maxPieceLength: Int
    private let unkScore: Double

    private struct Piece: Sendable {
        let id: Int
        let score: Double
    }

    static let metaspace = "\u{2581}"

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = root["model"] as? [String: Any]
        else { throw TokenizerError.unsupportedFormat("objet « model » absent") }
        guard (model["type"] as? String) == "Unigram", let entries = model["vocab"] as? [[Any]] else {
            throw TokenizerError.unsupportedFormat("modèle \(model["type"] ?? "?") au lieu de Unigram")
        }

        var vocab: [String: Piece] = [:]
        var maxLength = 1
        var minScore = 0.0
        for (id, entry) in entries.enumerated() {
            guard let piece = entry.first as? String, let score = (entry.last as? NSNumber)?.doubleValue else { continue }
            if vocab[piece] == nil { vocab[piece] = Piece(id: id, score: score) }
            maxLength = max(maxLength, piece.unicodeScalars.count)
            minScore = min(minScore, score)
        }

        let addedTokens = root["added_tokens"] as? [[String: Any]] ?? []
        func specialID(_ content: String) -> Int? {
            addedTokens.first { $0["content"] as? String == content }?["id"] as? Int ?? vocab[content]?.id
        }
        let unkID = model["unk_id"] as? Int ?? specialID("<unk>") ?? 0
        guard let bos = specialID("<s>"), let eos = specialID("</s>") else {
            throw TokenizerError.unsupportedFormat("jetons <s> / </s> introuvables")
        }

        self.vocab = vocab
        self.maxPieceLength = maxLength
        self.unkScore = minScore - 10  // même pénalité que SentencePiece et 🤗 tokenizers
        self.unkID = unkID
        self.bosID = bos
        self.eosID = eos
        self.padID = specialID("<pad>") ?? unkID
    }

    /// Identifiants avec `<s>` et `</s>`, tronqués à `maxLength` jetons au total.
    public func encode(_ text: String, maxLength: Int? = nil) -> [Int] {
        var ids: [Int] = []
        for word in Self.normalize(text).split(separator: " ") {
            ids += viterbi(Self.metaspace + word)
            if let maxLength, ids.count >= maxLength - 2 { break }
        }
        if let maxLength { ids = Array(ids.prefix(max(0, maxLength - 2))) }
        return [bosID] + ids + [eosID]
    }

    static func normalize(_ text: String) -> String {
        text.precomposedStringWithCompatibilityMapping  // NFKC
            .replacingOccurrences(of: "``", with: "\"")
            .replacingOccurrences(of: "''", with: "\"")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Découpage le plus probable d'un mot (programmation dynamique sur les scalaires Unicode).
    private func viterbi(_ word: String) -> [Int] {
        let scalars = Array(word.unicodeScalars)
        let count = scalars.count
        var best = [Double](repeating: -.infinity, count: count + 1)
        var back = [(start: Int, id: Int)](repeating: (0, unkID), count: count + 1)
        best[0] = 0

        for start in 0..<count where best[start] > -.infinity {
            var piece = String.UnicodeScalarView()
            var hasSingleScalarPiece = false
            for end in (start + 1)...min(count, start + maxPieceLength) {
                piece.append(scalars[end - 1])
                guard let match = vocab[String(piece)] else { continue }
                let score = best[start] + match.score
                if score > best[end] {
                    best[end] = score
                    back[end] = (start, match.id)
                }
                if end == start + 1 { hasSingleScalarPiece = true }
            }
            if !hasSingleScalarPiece {
                let score = best[start] + unkScore
                if score > best[start + 1] {
                    best[start + 1] = score
                    back[start + 1] = (start, unkID)
                }
            }
        }

        var ids: [Int] = []
        var position = count
        while position > 0 {
            ids.append(back[position].id)
            position = back[position].start
        }
        ids.reverse()
        // Comme SentencePiece : des inconnus consécutifs ne forment qu'un seul <unk>.
        return ids.enumerated().compactMap { index, id in
            id == unkID && index > 0 && ids[index - 1] == unkID ? nil : id
        }
    }
}
