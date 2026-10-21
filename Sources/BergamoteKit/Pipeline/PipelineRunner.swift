import Foundation
import os

/// Fait tourner les workers d'indexation en arrière-plan.
///
/// - 2 workers « extract » (QoS utility) : la phase 1 rend un document cherchable en quelques secondes.
/// - 1 worker « enrich » (QoS background) : une seule session d'inférence à la fois, sur les
///   cœurs basse consommation, mise en pause selon `IndexingPolicy`.
public actor PipelineRunner {
    public struct Configuration: Sendable {
        public var extractionWorkers = 2
        public var idleDelay: Duration = .milliseconds(400)
        public var pauseCheckDelay: Duration = .seconds(15)

        public init() {}
    }

    let queue: JobQueue
    let indexer: DocumentIndexer
    let policy: IndexingPolicy
    let configuration: Configuration
    private var workers: [Task<Void, Never>] = []
    private let pause = OSAllocatedUnfairLock<String?>(initialState: nil)

    init(queue: JobQueue, indexer: DocumentIndexer, policy: IndexingPolicy, configuration: Configuration = .init()) {
        self.queue = queue
        self.indexer = indexer
        self.policy = policy
        self.configuration = configuration
    }

    public var isRunning: Bool { !workers.isEmpty }

    /// Raison de la pause de la phase 2, à afficher dans l'UI.
    public nonisolated var pauseReason: String? { pause.withLock { $0 } }

    public func start() {
        guard workers.isEmpty else { return }
        try? queue.releaseAllLeases()
        for _ in 0..<configuration.extractionWorkers {
            workers.append(spawn(stages: [.extract], priority: .utility))
        }
        workers.append(spawn(stages: [.enrich], priority: .background))
    }

    public func stop() {
        workers.forEach { $0.cancel() }
        workers.removeAll()
    }

    /// Traite toute la file immédiatement, sans politique de pause (tests, import en ligne de commande).
    public func drain() async throws {
        while let job = try queue.claim(stages: Stage.allCases) {
            do {
                try await indexer.process(job)
            } catch {
                try queue.fail(job, error: error)
            }
        }
    }

    private func spawn(stages: [Stage], priority: TaskPriority) -> Task<Void, Never> {
        let queue = queue, indexer = indexer, policy = policy, configuration = configuration, pause = pause
        return Task.detached(priority: priority) {
            while !Task.isCancelled {
                let reason = policy.pauseReason(for: stages)
                if stages.contains(.enrich) { pause.withLock { $0 = reason } }
                if reason != nil {
                    try? await Task.sleep(for: configuration.pauseCheckDelay)
                    continue
                }
                guard let job = try? queue.claim(stages: stages) else {
                    try? await Task.sleep(for: configuration.idleDelay)
                    continue
                }
                do {
                    try await indexer.process(job)
                } catch is CancellationError {
                    try? queue.release(job)
                    return
                } catch {
                    Logger.pipeline.error("Échec \(job.stage.rawValue, privacy: .public) doc \(job.documentId): \(error.localizedDescription, privacy: .public)")
                    try? queue.fail(job, error: error)
                }
            }
        }
    }
}

extension Logger {
    static let pipeline = Logger(subsystem: "com.example.bergamote", category: "pipeline")
}
