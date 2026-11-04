import AppKit
import BergamoteKit
import SwiftUI

/// Bergamote vit uniquement dans la barre des menus : pas de fenêtre principale, pas d'icône dans
/// le Dock (`LSUIElement` dans Info.plist). Le camembert s'ouvre depuis n'importe quelle app.
@main
struct BergamoteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Bergamote", systemImage: "chart.pie") {
            MenuBarPanel(model: appDelegate.radialMenu.model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.folderAccess)
        }
    }
}

/// Démarre la surveillance du geste au lancement : aucune fenêtre n'est nécessaire.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let folderAccess = FolderAccessStore()
    private(set) lazy var radialMenu = RadialMenuController(folderAccess: folderAccess)

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Utilitaire de fond : macOS ne doit pas le quitter parce qu'aucune fenêtre n'est ouverte.
        ProcessInfo.processInfo.disableAutomaticTermination("Surveillance du geste du camembert")
        // Pas d'icône dans le Dock, y compris avec `swift run` (binaire sans Info.plist).
        NSApp.setActivationPolicy(.accessory)
        radialMenu.startMonitoring()
    }
}
