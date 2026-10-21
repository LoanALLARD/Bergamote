import AppKit
import BergamoteKit
import SwiftUI

/// Fenêtre de la barre des menus : on y dépose des fichiers sans ouvrir la bibliothèque.
struct DropZoneView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
                .background(isTargeted ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down").font(.largeTitle)
                        Text("Déposez des documents à indexer").font(.headline)
                        Text("PDF, images, Word, texte. Tout reste sur ce Mac.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(height: 140)
                .dropDestination(for: URL.self) { urls, _ in
                    model.importItems(urls)
                    return true
                } isTargeted: { isTargeted = $0 }

            if model.inProgressCount > 0 {
                Label("\(model.inProgressCount) document(s) en cours d'analyse", systemImage: "sparkles")
            } else if let message = model.lastImportMessage {
                Text(message).foregroundStyle(.secondary)
            }
            if let reason = model.pauseReason {
                Label("Analyse en pause : \(reason)", systemImage: "pause.circle").foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button("Ouvrir la bibliothèque") {
                    openWindow(id: "library")
                    NSApp.activate()
                }
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
