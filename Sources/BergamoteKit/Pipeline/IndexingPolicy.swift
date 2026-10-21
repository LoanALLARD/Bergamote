import Foundation
import IOKit.ps

/// Décide si l'indexation de fond doit se mettre en pause. Seule la phase 2 (embeddings,
/// coûteuse) est suspendue : la phase 1 reste immédiate pour que la recherche lexicale le soit aussi.
public struct IndexingPolicy: Sendable {
    public var pauseOnLowPowerMode = true
    public var pauseOnThermalPressure = true
    /// Désactivé par défaut : les workers tournent déjà en QoS « background », que macOS
    /// place sur les cœurs basse consommation.
    public var pauseOnBattery = false

    public init() {}

    public func pauseReason(for stages: [Stage]) -> String? {
        guard stages.contains(.enrich) else { return nil }
        let info = ProcessInfo.processInfo
        if pauseOnLowPowerMode && info.isLowPowerModeEnabled {
            return "Mode économie d'énergie activé"
        }
        if pauseOnThermalPressure && (info.thermalState == .serious || info.thermalState == .critical) {
            return "Mac trop chaud"
        }
        if pauseOnBattery && Self.isOnBattery {
            return "Mac sur batterie"
        }
        return nil
    }

    public static var isOnBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else { return false }
        return (type as String) == kIOPSBatteryPowerValue
    }
}
