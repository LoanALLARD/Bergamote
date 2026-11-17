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
    /// Observé pour que le panneau se redessine quand la langue change.
    @AppStorage(Localization.preferenceKey) private var language = Localization.systemPreference

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.pie.fill").foregroundStyle(.tint)
                Text("Bergamote").font(.headline)
                Spacer()
                Toggle(L("menu.enable"), isOn: $isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("menu.drag_hint", ["source": L("source.finder")]))
                    .foregroundStyle(.secondary)
                gestureRow(key: WheelModifier(rawValue: conversionModifier), title: L("wheel.convert"), detail: L("menu.convert_detail"))
                gestureRow(key: WheelModifier(rawValue: toolsModifier), title: L("wheel.tools"), detail: L("menu.tools_detail"))
                Text(L("menu.drop_hint"))
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
                Button(L("menu.settings")) {
                    NSApp.activate()
                    openSettings()
                }
                Spacer()
                Button(L("menu.quit")) { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 320)
        .id(language)
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
