import Observation
import os
import ServiceManagement

/// Lancement à l'ouverture de session, par `SMAppService` : l'app apparaît dans
/// Réglages Système › Général › Ouverture, où l'utilisateur garde la main.
@MainActor
@Observable
final class LoginItem {
    private(set) var status = SMAppService.mainApp.status
    /// La dernière demande a échoué (app lancée hors d'un bundle, par exemple).
    private(set) var failed = false

    /// Avant la première inscription, macOS répond « introuvable » : ce n'est pas une erreur.
    var isEnabled: Bool { status == .enabled }
    /// macOS attend que l'utilisateur approuve l'élément dans Réglages Système.
    var needsApproval: Bool { status == .requiresApproval }

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
            failed = false
        } catch {
            failed = true
            Logger.wheel.error("Ouverture de session : \(error.localizedDescription, privacy: .public)")
        }
        refresh()
    }
}
