import Foundation
import GRDB
import Testing
@testable import BergamoteKit

/// Qualité de bout en bout sur le corpus d'essai (`swift scripts/make-samples.swift SampleDocs`).
///
///     BERGAMOTE_SAMPLES_DIR=SampleDocs swift test --filter Corpus
///
/// Sans `BERGAMOTE_MODELS_DIR`, c'est le repli lexical qui est mesuré.
@Suite("Corpus d'essai", .enabled(if: ProcessInfo.processInfo.environment["BERGAMOTE_SAMPLES_DIR"] != nil))
struct SampleCorpusTests {
    static let expectedTypes = [
        "facture-volt-fevrier-2025": "facture",
        "bail-appartement-lyon": "contrat",
        "bulletin-paie-mars-2025": "paie",
        "attestation-assurance": "attestation",
        "scan-avis-echeance-loyer": "loyer",
        "ticket-librairie": "recu",
        "courrier-resiliation": "courrier",
    ]

    /// (requête, document attendu en tête, piège lexical connu)
    static let queries = [
        // « payer » est rare et apparaît deux fois dans le bulletin (« net à payer ») : la recherche
        // par mots le place devant la facture. C'est le cas qu'un modèle sémantique doit corriger.
        ("montant total à payer pour l'électricité", "facture-volt-fevrier-2025", true),
        ("facture d'électricité de février", "facture-volt-fevrier-2025", false),
        ("salaire net du mois de mars", "bulletin-paie-mars-2025", false),
        ("assurance habitation", "attestation-assurance", false),
        ("quittance de loyer d'avril", "scan-avis-echeance-loyer", false),
        ("ticket de caisse librairie", "ticket-librairie", false),
        ("résilier mon abonnement internet", "courrier-resiliation", false),
        ("dépôt de garantie du bail", "bail-appartement-lyon", false),
    ]

    @Test func classifiesFindsAndExtracts() async throws {
        let samples = URL(fileURLWithPath: ProcessInfo.processInfo.environment["BERGAMOTE_SAMPLES_DIR"]!)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("corpus-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = try await BergamoteEngine.bootstrap(root: root, bundledModels: nil)
        let report = try await engine.importItems([samples])
        #expect(report.added.count == Self.expectedTypes.count)
        try await engine.runner.drain()

        let documents = try await engine.database.reader.read { db in try Document.fetchAll(db) }
        #expect(documents.allSatisfy { $0.status == .ready })

        // Classement : au moins 6 sur 7 sans aucun exemple validé.
        let misclassified = documents.filter { Self.expectedTypes[$0.title] != $0.docType }
        #expect(misclassified.count <= 1, "mal classés : \(misclassified.map { "\($0.title) → \($0.docType ?? "nil")" })")

        // Recherche : le bon document en tête pour chaque requête.
        for (query, expected, lexicalTrap) in Self.queries {
            let first = try await engine.search.search(query).first?.title
            if lexicalTrap && !engine.embedder.isSemantic {
                withKnownIssue("Limite de la recherche par mots, à revérifier avec CamemBERT") {
                    #expect(first == expected, "« \(query) » → \(first ?? "aucun résultat")")
                }
            } else {
                #expect(first == expected, "« \(query) » → \(first ?? "aucun résultat")")
            }
        }

        // Entités : pas de titre en capitales pris pour un nom, les rues reconnues comme lieux.
        var entities: [EntityRecord] = []
        for document in documents { entities += try await engine.entities(of: document.id!) }
        let names = entities.filter { [.person, .organization, .place].contains($0.kind) }
        #expect(!names.contains { !$0.value.contains(where: \.isLowercase) && !$0.value.contains(" ") }, "\(names.map(\.value))")
        #expect(!names.contains { $0.kind == .person && $0.value == "Jean Jaurès" })
        #expect(names.contains { $0.kind == .place && $0.value == "avenue Jean Jaurès" })
        #expect(entities.contains { $0.kind == .siret && $0.normalized == "44306184100047" })
    }
}
