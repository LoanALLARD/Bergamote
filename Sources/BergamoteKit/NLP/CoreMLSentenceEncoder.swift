import CoreML
import Foundation

/// Encodeur de phrases CamemBERT converti en Core ML par `scripts/convert_camembert.py`.
///
/// Le dossier du modèle contient :
/// - `Encoder.mlpackage` (ou `Encoder.mlmodelc` déjà compilé, comme le produit Xcode) ;
/// - `tokenizer.json` ;
/// - `bergamote-model.json` (manifeste ci-dessous).
///
/// Le mean pooling et la normalisation sont faits dans le graphe Core ML : le modèle renvoie
/// directement le vecteur de phrase, et peut tourner sur le Neural Engine.
public final class CoreMLSentenceEncoder: EmbeddingProvider, @unchecked Sendable {
    public struct Manifest: Codable, Sendable {
        public var modelID: String
        public var dimension: Int
        public var sequenceLength: Int
        public var queryPrefix: String
        public var passagePrefix: String
        public var outputName: String
    }

    public static let manifestFileName = "bergamote-model.json"

    public let modelID: String
    public let dimension: Int
    private let manifest: Manifest
    private let model: MLModel
    private let tokenizer: UnigramTokenizer
    private let lock = NSLock()

    private init(manifest: Manifest, model: MLModel, tokenizer: UnigramTokenizer) {
        self.manifest = manifest
        self.model = model
        self.tokenizer = tokenizer
        self.modelID = "coreml-\(manifest.modelID)"
        self.dimension = manifest.dimension
    }

    /// `true` si le dossier ressemble à un modèle Bergamote.
    public static func isModelDirectory(_ directory: URL) -> Bool {
        FileManager.default.fileExists(atPath: directory.appendingPathComponent(manifestFileName).path)
    }

    public static func load(from directory: URL, computeUnits: MLComputeUnits = .all) async throws -> CoreMLSentenceEncoder {
        let manifest = try JSONDecoder().decode(
            Manifest.self, from: Data(contentsOf: directory.appendingPathComponent(manifestFileName)))
        let tokenizer = try UnigramTokenizer(contentsOf: directory.appendingPathComponent("tokenizer.json"))
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        let compiledURL = try await compiledModel(in: directory, cacheKey: manifest.modelID)
        let model = try await MLModel.load(contentsOf: compiledURL, configuration: configuration)
        return CoreMLSentenceEncoder(manifest: manifest, model: model, tokenizer: tokenizer)
    }

    /// Renvoie `Encoder.mlmodelc`, en compilant le `.mlpackage` une fois dans les caches si besoin.
    static func compiledModel(in directory: URL, cacheKey: String) async throws -> URL {
        let fileManager = FileManager.default
        let shipped = directory.appendingPathComponent("Encoder.mlmodelc")
        if fileManager.fileExists(atPath: shipped.path) { return shipped }

        let package = directory.appendingPathComponent("Encoder.mlpackage")
        guard fileManager.fileExists(atPath: package.path) else {
            throw EmbeddingError.unavailable("ni Encoder.mlmodelc ni Encoder.mlpackage dans \(directory.lastPathComponent)")
        }
        let caches = try fileManager.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Bergamote/Models", isDirectory: true)
        let safeKey = cacheKey.replacingOccurrences(of: "/", with: "__")
        let cached = caches.appendingPathComponent("\(safeKey).mlmodelc")
        let packageDate = (try? fileManager.attributesOfItem(atPath: package.path)[.modificationDate] as? Date) ?? .distantPast
        let cachedDate = (try? fileManager.attributesOfItem(atPath: cached.path)[.modificationDate] as? Date) ?? .distantPast
        if fileManager.fileExists(atPath: cached.path), cachedDate >= packageDate { return cached }

        let compiled = try await MLModel.compileModel(at: package)
        try fileManager.createDirectory(at: caches, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: cached.path) { try fileManager.removeItem(at: cached) }
        try fileManager.moveItem(at: compiled, to: cached)
        return cached
    }

    public func embed(_ texts: [String], as input: EmbeddingInput) async throws -> [[Float]] {
        let prefix = input == .query ? manifest.queryPrefix : manifest.passagePrefix
        return try texts.map { try encode(prefix + $0) }
    }

    private func encode(_ text: String) throws -> [Float] {
        let length = manifest.sequenceLength
        let ids = tokenizer.encode(text, maxLength: length)
        let shape = [1, NSNumber(value: length)]
        let inputIDs = try MLMultiArray(shape: shape, dataType: .int32)
        let attentionMask = try MLMultiArray(shape: shape, dataType: .int32)
        for index in 0..<length {
            let isToken = index < ids.count
            inputIDs[index] = NSNumber(value: isToken ? ids[index] : tokenizer.padID)
            attentionMask[index] = NSNumber(value: isToken ? 1 : 0)
        }
        let features = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: inputIDs),
            "attention_mask": MLFeatureValue(multiArray: attentionMask),
        ])
        let output = try lock.withLock { try model.prediction(from: features) }
        guard let vector = output.featureValue(for: manifest.outputName)?.multiArrayValue else {
            throw EmbeddingError.missingOutput(manifest.outputName)
        }
        return Embeddings.normalized((0..<vector.count).map { vector[$0].floatValue })
    }
}
