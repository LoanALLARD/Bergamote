import Foundation
import NaturalLanguage

/// Normalisation lexicale pour FTS5, qui ne sait pas raciniser le français :
/// lemmatisation par NaturalLanguage (« factures » → « facture »), minuscules, sans accents.
/// Le même traitement est appliqué au texte indexé et à la requête.
public struct FrenchNormalizer: Sendable {
    public init() {}

    static let locale = Locale(identifier: "fr_FR")

    static let stopwords: Set<String> = [
        "a", "au", "aux", "avec", "ce", "ces", "cette", "dans", "de", "des", "du", "elle", "en", "et",
        "etre", "avoir", "il", "ils", "je", "la", "le", "les", "leur", "leurs", "lui", "ma", "mais", "me",
        "mes", "mon", "ne", "nous", "on", "ou", "par", "pas", "pour", "qu", "que", "qui", "sa", "se",
        "ses", "son", "sur", "ta", "te", "tes", "ton", "tu", "un", "une", "vos", "votre", "vous", "y",
        "c", "d", "j", "l", "m", "n", "s", "t",
    ]

    /// Lemmes du texte, dans l'ordre, ponctuation exclue.
    public func lemmas(_ text: String) -> [String] {
        guard !text.isEmpty else { return [] }
        // Élisions : « l'électricité » et « d'électricité » doivent donner le même terme.
        let text = text.replacingOccurrences(of: "['’]", with: " ", options: .regularExpression)
        let tagger = NLTagger(tagSchemes: [.lemma])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        tagger.setLanguage(.french, range: range)
        var result: [String] = []
        tagger.enumerateTags(in: range, unit: .word, scheme: .lemma, options: [.omitPunctuation, .omitWhitespace]) { tag, tokenRange in
            let word = tag?.rawValue ?? String(text[tokenRange])
            let folded = Self.fold(word)
            if !folded.isEmpty { result.append(folded) }
            return true
        }
        return result
    }

    /// Texte stocké dans la colonne FTS5 `lemmas`.
    public func indexText(_ text: String) -> String {
        lemmas(text).joined(separator: " ")
    }

    /// Termes significatifs d'une requête (sans mots vides).
    public func terms(_ query: String) -> [String] {
        var seen: Set<String> = []
        return lemmas(query).filter { term in
            !Self.stopwords.contains(term) && seen.insert(term).inserted
        }
    }

    /// Requête FTS5 : termes reliés par OR, le classement BM25 et la fusion avec la
    /// recherche sémantique se chargent de la pertinence.
    public func ftsQuery(_ query: String) -> String? {
        let terms = terms(query)
        guard !terms.isEmpty else { return nil }
        return terms.map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }.joined(separator: " OR ")
    }

    public static func fold(_ word: String) -> String {
        word.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale)
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
