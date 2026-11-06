import BergamoteKit
import SwiftUI

struct SettingsView: View {
    @Environment(FolderAccessStore.self) private var folderAccess
    @AppStorage(RadialMenuController.enabledKey) private var isEnabled = true
    @AppStorage(RadialMenuController.conversionModifierKey) private var conversionModifier = WheelModifier.shift.rawValue
    @AppStorage(RadialMenuController.toolsModifierKey) private var toolsModifier = WheelModifier.command.rawValue
    @AppStorage(RadialMenuController.soundKey) private var playsSound = true

    private let choices: [WheelModifier] = [.shift, .control, .option, .command]

    var body: some View {
        Form {
            Section {
                Toggle("Activer le camembert", isOn: $isEnabled)
                Picker("Camembert de conversion", selection: $conversionModifier) {
                    ForEach(choices, id: \.rawValue) { Text($0.symbol).tag($0.rawValue) }
                }
                Picker("Camembert d'outils", selection: $toolsModifier) {
                    ForEach(choices, id: \.rawValue) { Text($0.symbol).tag($0.rawValue) }
                }
                if conversionModifier == toolsModifier {
                    Text("Les deux camemberts utilisent la même touche : seul celui de conversion s'ouvrira.")
                        .font(.callout).foregroundStyle(.orange)
                }
                HStack {
                    Toggle("Clic au passage d'une part", isOn: $playsSound)
                    Spacer()
                    Button("Écouter") {
                        WheelSound.tick(force: true)
                        Task {
                            try? await Task.sleep(for: .milliseconds(140))
                            WheelSound.tick(force: true)
                        }
                    }
                }
            } footer: {
                Text("Glissez des fichiers depuis le Finder, puis tapez la touche choisie (ou maintenez-la avant de glisser) : le camembert s'ouvre sous le curseur. Lâchez les fichiers sur une part.")
            }

            Section {
                ForEach(folderAccess.grants, id: \.self) { folder in
                    HStack {
                        Label(folder.path(percentEncoded: false), systemImage: "folder")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Retirer") { folderAccess.remove(folder) }
                    }
                }
                if FolderAccessStore.isSandboxed {
                    Button("Autoriser le dossier personnel…") {
                        _ = folderAccess.requestAccess(covering: [FolderAccessStore.homeFolder])
                    }
                }
            } header: {
                Text("Enregistrement à côté des originaux")
            } footer: {
                Text("Les résultats sont créés dans le même dossier que le fichier d'origine, qui n'est jamais modifié. macOS demande d'autoriser une fois votre dossier personnel : tous les dossiers qu'il contient sont inclus.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}
