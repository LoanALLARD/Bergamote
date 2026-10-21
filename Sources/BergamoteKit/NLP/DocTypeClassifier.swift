import Foundation

public struct DocTypeDefinition: Sendable, Hashable, Identifiable {
    public let id: String
    public let label: String
    /// Description utilisée pour le classement « zero-shot », avant tout exemple validé. Elle sert
    /// aussi bien à un modèle sémantique qu'au repli lexical : on y met le vocabulaire typique du type.
    public let description: String

    public static let defaults: [DocTypeDefinition] = [
        .init(id: "facture", label: "Facture", description: "Facture d'un fournisseur à un client : numéro de facture, fourniture, consommation, total HT, TVA, total TTC, montant à régler, échéance, règlement par virement."),
        .init(id: "devis", label: "Devis", description: "Devis ou proposition commerciale : estimation de prix, détail des prestations, durée de validité de l'offre, bon pour accord."),
        .init(id: "contrat", label: "Contrat", description: "Contrat, bail ou conditions générales : entre les soussignés, parties, articles, objet, durée, location, résiliation, préavis, fait en deux exemplaires, signatures."),
        .init(id: "paie", label: "Bulletin de paie", description: "Bulletin de paie : employeur, salarié, emploi, salaire de base brut, cotisations salariales, CSG, net à payer avant impôt, prélèvement à la source, congés payés."),
        .init(id: "impots", label: "Avis d'imposition", description: "Document fiscal : avis d'impôt sur le revenu, taxe foncière, revenu fiscal de référence, numéro fiscal, direction des finances publiques."),
        .init(id: "banque", label: "Relevé bancaire", description: "Relevé de compte bancaire : solde, opérations au débit et au crédit, virements, prélèvements, IBAN, période."),
        .init(id: "attestation", label: "Attestation", description: "Attestation ou certificat : atteste que, titulaire du contrat, assurance, garantie, domicile, délivrée pour servir et valoir ce que de droit."),
        .init(id: "loyer", label: "Quittance de loyer", description: "Quittance ou avis d'échéance de loyer : bailleur, locataire, logement, loyer hors charges, provision sur charges, total réglé, période."),
        .init(id: "recu", label: "Ticket de caisse", description: "Ticket de caisse ou reçu d'achat : magasin, articles, prix, total, carte bancaire, espèces, merci de votre visite."),
        .init(id: "courrier", label: "Courrier", description: "Lettre ou courrier : objet, madame, monsieur, je vous prie, veuillez agréer, salutations distinguées, demande."),
    ]
}

public struct DocTypePrediction: Sendable, Hashable {
    public enum Decision: String, Sendable {
        case automatic, suggested, unclassified
    }

    public var docType: String
    public var confidence: Double
    public var decision: Decision
}

/// Classement du type de document **sans deuxième passe d'encodeur** : on réutilise le
/// vecteur déjà calculé pour la recherche, et on le compare à un prototype par classe.
///
/// - Sans exemple, le prototype est l'embedding de la description (zero-shot).
/// - Chaque type validé par l'utilisateur devient un exemple : le prototype se recalcule en
///   quelques microsecondes, hors ligne, sans réentraînement. C'est l'apprentissage local.
/// - L'application automatique exige une confiance haute **et** des exemples validés pour la
///   classe : jamais d'application automatique sur du pur zero-shot.
public actor DocTypeClassifier {
    public let definitions: [DocTypeDefinition]
    public var temperature: Float = 0.05
    public var autoApplyThreshold = 0.90
    public var suggestThreshold = 0.45
    public var minimumExamplesForAutoApply = 3

    private let embedder: any EmbeddingProvider
    private var descriptionVectors: [String: [Float]]?
    private var examples: [Int64: (docType: String, vector: [Float])] = [:]

    public init(embedder: any EmbeddingProvider, definitions: [DocTypeDefinition] = DocTypeDefinition.defaults) {
        self.embedder = embedder
        self.definitions = definitions
        // Les similarités lexicales sont plus étalées que les sémantiques : à température égale,
        // le repli afficherait des confidences de 99 % pour un simple recoupement de mots-clés.
        self.temperature = embedder.isSemantic ? 0.05 : 0.1
    }

    public func setExample(documentID: Int64, docType: String, vector: [Float]) {
        examples[documentID] = (docType, vector)
    }

    public func removeExample(documentID: Int64) {
        examples[documentID] = nil
    }

    public func exampleCount(for docType: String) -> Int {
        examples.values.filter { $0.docType == docType }.count
    }

    public func predict(_ documentVector: [Float]) async throws -> DocTypePrediction? {
        let prototypes = try await prototypes()
        guard !prototypes.isEmpty else { return nil }
        let similarities = prototypes.map { (docType: $0.key, similarity: Embeddings.dot(documentVector, $0.value)) }
        // Softmax à température : transforme des similarités proches en probabilités contrastées.
        let maxSimilarity = similarities.map(\.similarity).max() ?? 0
        let weights = similarities.map { exp(Double(($0.similarity - maxSimilarity) / temperature)) }
        let total = weights.reduce(0, +)
        guard let bestIndex = weights.indices.max(by: { weights[$0] < weights[$1] }), total > 0 else { return nil }
        let docType = similarities[bestIndex].docType
        let confidence = weights[bestIndex] / total

        let decision: DocTypePrediction.Decision
        if confidence >= autoApplyThreshold && exampleCount(for: docType) >= minimumExamplesForAutoApply {
            decision = .automatic
        } else if confidence >= suggestThreshold {
            decision = .suggested
        } else {
            decision = .unclassified
        }
        return DocTypePrediction(docType: docType, confidence: confidence, decision: decision)
    }

    private func prototypes() async throws -> [String: [Float]] {
        let descriptions = try await descriptionEmbeddings()
        var result: [String: [Float]] = [:]
        for definition in definitions {
            var members = examples.values.filter { $0.docType == definition.id }.map(\.vector)
            if let description = descriptions[definition.id] { members.append(description) }
            result[definition.id] = Embeddings.mean(members)
        }
        return result
    }

    private func descriptionEmbeddings() async throws -> [String: [Float]] {
        if let descriptionVectors { return descriptionVectors }
        let vectors = try await embedder.embed(definitions.map { "\($0.label). \($0.description)" }, as: .passage)
        let computed = Dictionary(uniqueKeysWithValues: zip(definitions.map(\.id), vectors))
        descriptionVectors = computed
        return computed
    }
}
