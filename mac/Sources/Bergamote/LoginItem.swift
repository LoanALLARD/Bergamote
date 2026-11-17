import Observation
import os
import ServiceManagement

/// Lancement à l'ouverture de session, par `SMAppService` : l'app apparaît dans
/// Réglages Système › Général › Ouverture, où l'utilisateur garde la main.
@MainActor
@Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status

    var isEnabled: Bool { status == .enabled }
    /// macOS attend que l'utilisateur approuve l'élément dans Réglages Système.
    var needsApproval: Bool { status == .requiresApproval }
    /// Hors d'un bundle installé (`swift run`), macOS ne sait pas quoi lancer.
    var isAvailable: Bool { status != .notFound }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            Logger.wheel.error("Ouverture de session : \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }
}
