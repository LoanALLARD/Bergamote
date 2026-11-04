import AppKit
import BergamoteKit
import SwiftUI

@main
struct BergamoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        Window("Bergamote", id: "library") {
            LibraryView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Importer des documents…") { model.isImporterVisible = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .textEditing) {
                Button("Rechercher partout…") { model.isPaletteVisible = true }
                    .keyboardShortcut("k")
            }
        }

        // Point d'entrée rapide : on dépose un fichier sans ouvrir la fenêtre.
        MenuBarExtra("Bergamote", systemImage: "doc.text.magnifyingglass") {
            DropZoneView()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

/// Possède le modèle et démarre le moteur au lancement, que des fenêtres soient ouvertes ou non :
/// le camembert doit surveiller le geste même quand la bibliothèque est fermée.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Utilitaire de fond : macOS ne doit pas le quitter parce qu'aucune fenêtre n'est ouverte.
        ProcessInfo.processInfo.disableAutomaticTermination("Surveillance du geste du camembert")
        // Nécessaire avec `swift run` (binaire hors bundle .app) pour obtenir une fenêtre au premier plan.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        Task { await model.start() }
    }

    /// « Ouvrir avec Bergamote », dépôt sur l'icône du Dock (types déclarés dans Info.plist).
    /// Sous sandbox, macOS accorde l'accès aux fichiers ainsi ouverts. Le modèle met les fichiers
    /// en attente si le moteur n'a pas encore démarré.
    func application(_ application: NSApplication, open urls: [URL]) {
        model.importItems(urls)
    }

    /// Fermer la bibliothèque ne quitte pas l'app : le camembert et la barre des menus restent actifs.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
