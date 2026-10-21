import Foundation
import Testing
@testable import BergamoteKit

@Suite("Texte : entités, découpage, normalisation")
struct TextTests {
    @Test func extractsValidatedEntitiesFromInvoice() {
        let entities = EntityExtractor().extract(from: Samples.invoice, page: 1)
        func values(_ kind: EntityKind) -> Set<String> { Set(entities.filter { $0.kind == kind }.compactMap(\.normalized)) }

        #expect(values(.iban) == ["FR7630006000011234567890189"])
        #expect(values(.siret) == ["73282932000074"])
        #expect(values(.amount).isSuperset(of: ["1234.56 EUR", "1028.80 EUR", "205.76 EUR"]))
        #expect(values(.date).isSuperset(of: ["2025-02-01", "2025-02-28", "2025-03-15"]))
        #expect(values(.email) == ["facturation@volt-fils.fr"])
        #expect(values(.phone) == ["+33472001122"])
    }

    @Test func rejectsChecksumFailures() {
        let text = "IBAN FR76 3000 6000 0112 3456 7890 188 – SIRET 732 829 320 00075 – le 31/02/2025"
        let kinds = Set(EntityExtractor().extract(from: text, page: nil).map(\.kind))
        #expect(!kinds.contains(.iban))
        #expect(!kinds.contains(.siret))
        #expect(!kinds.contains(.date))
    }

    @Test func ibanDigitsAreNotReadAsPhoneNumber() {
        let entities = EntityExtractor().extract(from: "IBAN : FR76 3000 6000 0112 3456 7890 189", page: nil)
        #expect(entities.filter { $0.kind == .phone }.isEmpty)
    }

    @Test func lemmatizesFrenchForFullText() {
        let terms = FrenchNormalizer().terms("Les factures d'électricité")
        #expect(terms.contains("facture"))
        #expect(terms.contains("electricite"))
        #expect(!terms.contains("les"))
    }

    @Test func elisionsYieldTheSameTerm() {
        let normalizer = FrenchNormalizer()
        #expect(normalizer.terms("pour l'électricité") == ["electricite"])
        #expect(normalizer.terms("fourniture d’électricité").contains("electricite"))
    }

    @Test func dropsHeadingWordsAndRecognisesStreets() {
        let text = "AVIS D'ÉCHÉANCE – LOYER\nLocataire : Camille Martin, 8 avenue Jean Jaurès, 69007 Lyon"
        let names = EntityExtractor().names(in: text, page: 1)
        #expect(!names.contains { $0.value == "LOYER" || $0.value == "AVIS" })
        #expect(names.contains { $0.kind == .place && $0.value == "avenue Jean Jaurès" })
        #expect(!names.contains { $0.kind == .person && $0.value == "Jean Jaurès" })
    }

    @Test func chunksStayWithinPagesAndBudget() {
        let longPage = (1...60).map { "Ligne \($0) : clause contractuelle sur les obligations du locataire et du bailleur." }
        let document = ExtractedDocument(pages: [
            ExtractedPage(number: 1, blocks: longPage.map { TextBlock(text: $0, bbox: NormalizedRect(CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.02))) }, usedOCR: false),
            ExtractedPage(number: 2, blocks: [TextBlock(text: "Signatures des parties.")], usedOCR: false),
        ])
        let chunker = Chunker()
        let drafts = chunker.chunk(document)
        #expect(drafts.count > 3)
        #expect(drafts.allSatisfy { $0.content.count <= chunker.maxLength + 100 })
        #expect(drafts.last?.page == 2)
        #expect(drafts.last?.content == "Signatures des parties.")
        #expect(drafts.first?.bbox != nil)
    }

    @Test func splitsVeryLongParagraphs() {
        let paragraph = String(repeating: "Une phrase assez longue sur la gestion documentaire. ", count: 80)
        let drafts = Chunker().chunk(ExtractedDocument(pages: [ExtractedPage(number: 1, blocks: [TextBlock(text: paragraph)], usedOCR: false)]))
        #expect(drafts.count >= 3)
        #expect(drafts.allSatisfy { $0.content.count <= Chunker().maxLength })
    }
}
