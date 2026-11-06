import AppKit
import BergamoteKit
import SwiftUI

/// Le panneau de l'icône de la barre des menus : rappel du geste, dernier résultat, réglages.
struct MenuBarPanel: View {
    let model: RadialMenuModel
    @Environment(\.openSettings) private var openSettings
    @AppStorage(RadialMenuController.enabledKey) private var isEnabled = true
    @AppStorage(RadialMenuController.conversionModifierKey) private var conversionModifier = WheelModifier.shift.rawValue
    @AppStorage(RadialMenuController.toolsModifierKey) private var toolsModifier = WheelModifier.command.rawValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.pie.fill").foregroundStyle(.tint)
                Text("Bergamote").font(.headline)
                Spacer()
                Toggle("Activer", isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Glissez des fichiers depuis le Finder, puis :")
                    .foregroundStyle(.secondary)
                gestureRow(key: WheelModifier(rawValue: conversionModifier), title: "Convertir", detail: "PNG, JPEG, HEIC, PDF, DOCX…")
                gestureRow(key: WheelModifier(rawValue: toolsModifier), title: "Outils", detail: "compresser, anonymiser, OCR…")
                Text("Lâchez-les sur une part : le résultat apparaît à côté de l'original.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .opacity(isEnabled ? 1 : 0.5)

            if let result = model.lastResult {
                Label(result, systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Button("Réglages…") {
                    NSApp.activate()
                    openSettings()
                }
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
    }

    private func gestureRow(key: WheelModifier, title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Text(key.symbol)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(width: 26, height: 22)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            Text(title).fontWeight(.medium)
            Text(detail).foregroundStyle(.secondary).lineLimit(1)
        }
    }
}
