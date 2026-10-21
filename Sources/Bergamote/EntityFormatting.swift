import BergamoteKit
import Foundation

extension EntityRecord {
    /// Valeur lisible : dates et montants au format local, IBAN, SIRET et téléphone groupés.
    var displayValue: String {
        guard let normalized else { return value }
        switch kind {
        case .date:
            return Self.isoDay.date(from: normalized)?.formatted(date: .long, time: .omitted) ?? value
        case .amount:
            let number = normalized.split(separator: " ").first.map(String.init) ?? normalized
            return Decimal(string: number)?.formatted(.currency(code: "EUR")) ?? value
        case .iban:
            return Self.grouped(normalized, sizes: Array(repeating: 4, count: 9))
        case .siret:
            return Self.grouped(normalized, sizes: [3, 3, 3, 5])
        case .siren:
            return Self.grouped(normalized, sizes: [3, 3, 3])
        case .phone where normalized.hasPrefix("+33") && normalized.count == 12:
            return Self.grouped("0" + normalized.dropFirst(3), sizes: [2, 2, 2, 2, 2])
        default:
            return normalized
        }
    }

    private static let isoDay: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func grouped(_ text: String, sizes: [Int]) -> String {
        var groups: [Substring] = []
        var rest = Substring(text)
        for size in sizes where !rest.isEmpty {
            groups.append(rest.prefix(size))
            rest = rest.dropFirst(size)
        }
        if !rest.isEmpty { groups.append(rest) }
        return groups.joined(separator: " ")
    }
}
