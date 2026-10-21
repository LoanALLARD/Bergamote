import AppKit
import BergamoteKit
import SwiftUI

@main
struct BergamoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Bergamote", id: "library") {
            LibraryView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 600)
                .task {
                    appDelegate.attach(model)
                    await model.start()
                }
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
                .task {
                    appDelegate.attach(model)
                    await model.start()
                }
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private var pendingURLs: [URL] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nécessaire avec `swift run` (binaire hors bundle .app) pour obtenir une fenêtre au premier plan.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// « Ouvrir avec Bergamote », dépôt sur l'icône du Dock (types déclarés dans Info.plist).
    /// Sous sandbox, macOS accorde l'accès aux fichiers ainsi ouverts.
    func application(_ application: NSApplication, open urls: [URL]) {
        if let model {
            model.importItems(urls)
        } else {
            pendingURLs += urls
        }
    }

    func attach(_ model: AppModel) {
        self.model = model
        if !pendingURLs.isEmpty {
            model.importItems(pendingURLs)
            pendingURLs = []
        }
    }
}
