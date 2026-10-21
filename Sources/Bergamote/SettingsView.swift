import BergamoteKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(RadialMenuController.enabledKey) private var isEnabled = true
    @AppStorage(RadialMenuController.conversionModifierKey) private var conversionModifier = WheelModifier.shift.rawValue
    @AppStorage(RadialMenuController.toolsModifierKey) private var toolsModifier = WheelModifier.command.rawValue
    @AppStorage(RadialMenuController.revealResultsKey) private var revealResults = true

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
            } footer: {
                Text("Glissez des fichiers depuis le Finder, puis tapez la touche choisie : le camembert s'ouvre sous le curseur. Lâchez les fichiers sur une part.")
            }
            Section {
                Toggle("Afficher le résultat dans le Finder", isOn: $revealResults)
            } footer: {
                Text("Les fichiers créés sont rangés dans Téléchargements › Bergamote. Les originaux ne sont jamais modifiés.")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }
}
