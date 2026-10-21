import Foundation

/// Découpe un document extrait en passages (chunks) pour l'index.
///
/// Un chunk ne traverse jamais une page (le surlignage dans l'aperçu reste simple) et vise
/// ~900 caractères, soit ~220 tokens CamemBERT : il tient dans la fenêtre de 256 tokens du
/// modèle Core ML, préfixe compris.
public struct Chunker: Sendable {
    public var targetLength = 900
    public var maxLength = 1_100
    /// Le dernier bloc d'un chunk est répété au début du suivant s'il est plus court que ça.
    public var overlapLength = 200

    public init() {}

    public struct Draft: Sendable, Hashable {
        public var page: Int?
        public var bbox: NormalizedRect?
        public var content: String
    }

    public func chunk(_ document: ExtractedDocument) -> [Draft] {
        var drafts: [Draft] = []
        for page in document.pages {
            var current: [TextBlock] = []
            var length = 0
            // Faux si `current` ne contient que le bloc de chevauchement, déjà émis.
            var hasNewContent = false

            func emit() {
                let content = current.map(\.text).joined(separator: "\n")
                let boxes = current.compactMap(\.bbox)
                let bbox = boxes.dropFirst().reduce(boxes.first) { $0?.union($1) }
                drafts.append(Draft(page: page.number, bbox: bbox, content: content))
            }

            for block in page.blocks.flatMap(split) {
                if hasNewContent && length + block.text.count > targetLength {
                    emit()
                    if let last = current.last, last.text.count <= overlapLength, current.count > 1 {
                        current = [last]
                        length = last.text.count + 1
                    } else {
                        current = []
                        length = 0
                    }
                    hasNewContent = false
                }
                current.append(block)
                length += block.text.count + 1
                hasNewContent = true
            }
            // Fin de page : pas de chevauchement vers la page suivante.
            if hasNewContent { emit() }
        }
        return drafts
    }

    /// Coupe un bloc trop long (paragraphe sans retour à la ligne) aux frontières de phrases.
    func split(_ block: TextBlock) -> [TextBlock] {
        guard block.text.count > maxLength else { return [block] }
        var pieces: [TextBlock] = []
        var current = ""
        block.text.enumerateSubstrings(in: block.text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            if current.count + sentence.count > targetLength, !current.isEmpty {
                pieces.append(TextBlock(text: current, bbox: block.bbox))
                current = ""
            }
            current += sentence
        }
        if !current.isEmpty { pieces.append(TextBlock(text: current, bbox: block.bbox)) }
        // Une « phrase » sans ponctuation peut encore dépasser : découpe brute en dernier recours.
        return pieces.flatMap { piece -> [TextBlock] in
            guard piece.text.count > maxLength else { return [piece] }
            var result: [TextBlock] = []
            var rest = Substring(piece.text)
            while !rest.isEmpty {
                result.append(TextBlock(text: String(rest.prefix(targetLength)), bbox: piece.bbox))
                rest = rest.dropFirst(targetLength)
            }
            return result
        }
    }
}
