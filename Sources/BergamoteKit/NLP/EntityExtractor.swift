import Foundation
import NaturalLanguage

public enum EntityKind: String, Codable, Sendable, CaseIterable {
    case person, organization, place
    case date, amount, iban, siret, siren, email, phone

    public var label: String {
        switch self {
        case .person: "Personnes"
        case .organization: "Organisations"
        case .place: "Lieux"
        case .date: "Dates"
        case .amount: "Montants"
        case .iban: "IBAN"
        case .siret: "SIRET"
        case .siren: "SIREN"
        case .email: "E-mails"
        case .phone: "Téléphones"
        }
    }
}

public struct ExtractedEntity: Sendable, Hashable {
    public var kind: EntityKind
    public var value: String
    public var normalized: String?
    public var confidence: Double
    public var page: Int?
}

/// Extraction d'entités : NER de NaturalLanguage pour personnes, organisations et lieux,
/// expressions régulières **validées** (Luhn, modulo 97, calendrier) pour les champs à forte
/// valeur. Une NER seule (CamemBERT compris) n'est pas assez fiable sur ces champs.
///
/// Pour brancher une NER CamemBERT Core ML, ajouter un passage dans `extract` : le reste
/// (déduplication, stockage, affichage) ne change pas.
public struct EntityExtractor: Sendable {
    public init() {}

    public func extract(from text: String, page: Int?) -> [ExtractedEntity] {
        var claimed: [NSRange] = []
        var entities: [ExtractedEntity] = []
        // Ordre important : un IBAN ou un SIRET « réserve » ses chiffres, qui ne seront pas
        // relus comme un numéro de téléphone ou une date.
        for rule in Self.rules {
            for match in rule.regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let range = match.range(at: rule.captureGroup)
                guard range.location != NSNotFound,
                      !claimed.contains(where: { NSIntersectionRange($0, range).length > 0 }),
                      let swiftRange = Range(range, in: text)
                else { continue }
                let value = String(text[swiftRange])
                guard let normalized = rule.normalize(value, match, text) else { continue }
                claimed.append(range)
                entities.append(ExtractedEntity(kind: rule.kind, value: value, normalized: normalized, confidence: 0.99, page: page))
            }
        }
        entities += names(in: text, page: page, excluding: claimed)
        return entities
    }

    static func deduplicated(_ entities: [ExtractedEntity]) -> [ExtractedEntity] {
        var seen: Set<String> = []
        return entities.filter { entity in
            seen.insert("\(entity.kind.rawValue)|\((entity.normalized ?? entity.value).lowercased())").inserted
        }
    }

    // MARK: Noms propres (NaturalLanguage)

    func names(in text: String, page: Int?, excluding claimed: [NSRange] = []) -> [ExtractedEntity] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        let range = text.startIndex..<text.endIndex
        tagger.setLanguage(.french, range: range)
        var result: [ExtractedEntity] = []
        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: [.omitWhitespace, .omitPunctuation, .joinNames]) { tag, tokenRange in
            let kind: EntityKind? = switch tag {
            case .personalName?: .person
            case .organizationName?: .organization
            case .placeName?: .place
            default: nil
            }
            let value = String(text[tokenRange])
            let nsRange = NSRange(tokenRange, in: text)
            guard let kind,
                  !claimed.contains(where: { NSIntersectionRange($0, nsRange).length > 0 }),
                  // Un mot isolé tout en capitales (« LOYER », « SIRET ») est un titre ou un sigle.
                  value.contains(where: \.isLowercase) || value.contains(" ")
            else { return true }

            // « 8 avenue Jean Jaurès » : un nom de rue, pas une personne.
            let lookBehind = text.index(tokenRange.lowerBound, offsetBy: -24, limitedBy: text.startIndex) ?? text.startIndex
            let before = String(text[lookBehind..<tokenRange.lowerBound])
            if let match = Self.streetPrefix.firstMatch(in: before, range: NSRange(before.startIndex..., in: before)),
               let streetRange = Range(match.range, in: before) {
                result.append(ExtractedEntity(kind: .place, value: before[streetRange] + value, normalized: nil, confidence: 0.6, page: page))
            } else {
                result.append(ExtractedEntity(kind: kind, value: value, normalized: nil, confidence: 0.7, page: page))
            }
            return true
        }
        return result
    }

    static let streetPrefix = regex(
        #"(?i)\b(?:rue|avenue|av\.|boulevard|bd|place|quai|all[ée]e|impasse|chemin|cours|route|square)\s+(?:de la |de l'|du |des |de |d')?$"#)

    // MARK: Règles

    struct Rule: @unchecked Sendable {
        let kind: EntityKind
        let regex: NSRegularExpression
        var captureGroup = 0
        /// Renvoie la forme normalisée, ou `nil` si la valeur ne passe pas la validation.
        let normalize: @Sendable (String, NSTextCheckingResult, String) -> String?
    }

    static let rules: [Rule] = [
        Rule(kind: .iban, regex: regex(#"\b[A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,4})?\b"#)) { value, _, _ in
            let compact = value.replacingOccurrences(of: " ", with: "")
            return isValidIBAN(compact) ? compact : nil
        },
        Rule(kind: .siret, regex: regex(#"\b\d{3} ?\d{3} ?\d{3} ?\d{5}\b"#)) { value, _, _ in
            let digits = value.filter(\.isNumber)
            return luhn(digits) ? digits : nil
        },
        Rule(kind: .siren, regex: regex(#"(?i)\b(?:siren|rcs)\b[^\d\n]{0,25}(\d{3} ?\d{3} ?\d{3})\b"#), captureGroup: 1) { value, _, _ in
            let digits = value.filter(\.isNumber)
            return luhn(digits) ? digits : nil
        },
        Rule(kind: .email, regex: regex(#"(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#)) { value, _, _ in
            value.lowercased()
        },
        Rule(kind: .amount, regex: regex(#"(?i)(?<![\d,.])(\d{1,3}(?:[   .]\d{3})+|\d+)(?:,(\d{1,2}))?\s?(?:€|EUR\b|euros?\b)"#)) { _, match, text in
            guard let integerRange = Range(match.range(at: 1), in: text) else { return nil }
            let integer = text[integerRange].filter(\.isNumber)
            var cents = "00"
            if let centsRange = Range(match.range(at: 2), in: text) {
                cents = String(text[centsRange]).padding(toLength: 2, withPad: "0", startingAt: 0)
            }
            return "\(integer).\(cents) EUR"
        },
        Rule(kind: .date, regex: regex(#"\b(0?[1-9]|[12]\d|3[01])[/.-](0?[1-9]|1[0-2])[/.-]((?:19|20)\d{2})\b"#)) { _, match, text in
            isoDate(day: group(1, of: match, in: text), month: group(2, of: match, in: text), year: group(3, of: match, in: text))
        },
        Rule(kind: .date, regex: regex(#"(?i)\b(1er|0?[1-9]|[12]\d|3[01])\s+(janvier|f[ée]vrier|mars|avril|mai|juin|juillet|ao[uû]t|septembre|octobre|novembre|d[ée]cembre)\s+((?:19|20)\d{2})\b"#)) { _, match, text in
            let day = group(1, of: match, in: text).replacingOccurrences(of: "er", with: "")
            let month = monthNumber(group(2, of: match, in: text))
            return isoDate(day: day, month: month.map(String.init) ?? "", year: group(3, of: match, in: text))
        },
        Rule(kind: .phone, regex: regex(#"(?<![\d])(?:\+33 ?|0)[1-9](?:[ .-]?\d{2}){4}(?![\d])"#)) { value, _, _ in
            let digits = value.filter(\.isNumber)
            return digits.hasPrefix("33") ? "+\(digits)" : "+33\(digits.dropFirst())"
        },
    ]

    static func regex(_ pattern: String) -> NSRegularExpression {
        // Motifs constants : une erreur ici est un bug de développement.
        try! NSRegularExpression(pattern: pattern)
    }

    static func group(_ index: Int, of match: NSTextCheckingResult, in text: String) -> String {
        Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
    }

    // MARK: Validateurs

    /// Clé de Luhn, utilisée par le SIREN (9 chiffres) et le SIRET (14 chiffres).
    static func luhn(_ digits: String) -> Bool {
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return false }
        var sum = 0
        for (index, character) in digits.reversed().enumerated() {
            var digit = character.wholeNumberValue ?? 0
            if index % 2 == 1 {
                digit *= 2
                if digit > 9 { digit -= 9 }
            }
            sum += digit
        }
        return sum % 10 == 0
    }

    /// Contrôle ISO 13616 : modulo 97 sur l'IBAN réarrangé doit valoir 1.
    static func isValidIBAN(_ iban: String) -> Bool {
        guard (15...34).contains(iban.count) else { return false }
        let rearranged = iban.dropFirst(4) + iban.prefix(4)
        var remainder = 0
        for character in rearranged {
            guard let value = character.isNumber ? character.wholeNumberValue : character.isLetter ? Int(character.asciiValue ?? 0) - 55 : nil,
                  value >= 0, value < 36
            else { return false }
            for digit in String(value) {
                remainder = (remainder * 10 + (digit.wholeNumberValue ?? 0)) % 97
            }
        }
        return remainder == 1
    }

    static func isoDate(day: String, month: String, year: String) -> String? {
        guard let d = Int(day), let m = Int(month), let y = Int(year) else { return nil }
        var components = DateComponents(year: y, month: m, day: d)
        components.calendar = Calendar(identifier: .gregorian)
        guard components.isValidDate else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    static func monthNumber(_ name: String) -> Int? {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        let months = ["janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout", "septembre", "octobre", "novembre", "decembre"]
        return months.firstIndex(of: folded).map { $0 + 1 }
    }
}
