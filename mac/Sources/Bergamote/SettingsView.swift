import BergamoteKit
import SwiftUI

struct SettingsView: View {
    @Environment(FolderAccessStore.self) private var folderAccess
    @AppStorage(RadialMenuController.enabledKey) private var isEnabled = true
    @AppStorage(RadialMenuController.conversionModifierKey) private var conversionModifier = WheelModifier.shift.rawValue
    @AppStorage(RadialMenuController.toolsModifierKey) private var toolsModifier = WheelModifier.command.rawValue
    @AppStorage(RadialMenuController.soundKey) private var playsSound = true
    @AppStorage(Localization.preferenceKey) private var language = Localization.systemPreference
    @State private var loginItem = LoginItem()

    private let choices: [WheelModifier] = [.shift, .control, .option, .command]

    /// La langue est appliquée au cœur avant que la vue se redessine dans cette langue.
    private var languageSelection: Binding<String> {
        Binding(
            get: { language },
            set: { preference in
                Localization.apply(preference: preference)
                language = preference
            })
    }

    var body: some View {
        Form {
            Section {
                Toggle(L("settings.enable"), isOn: $isEnabled)
                Picker(L("settings.conversion_key"), selection: $conversionModifier) {
                    ForEach(choices, id: \.rawValue) { Text($0.symbol).tag($0.rawValue) }
                }
                Picker(L("settings.tools_key"), selection: $toolsModifier) {
                    ForEach(choices, id: \.rawValue) { Text($0.symbol).tag($0.rawValue) }
                }
                if conversionModifier == toolsModifier {
                    Text(L("settings.key_conflict"))
                        .font(.callout).foregroundStyle(.orange)
                }
                HStack {
                    Toggle(L("settings.sound"), isOn: $playsSound)
                    Spacer()
                    Button(L("settings.listen")) {
                        WheelSound.tick(force: true)
                        Task {
                            try? await Task.sleep(for: .milliseconds(140))
                            WheelSound.tick(force: true)
                        }
                    }
                }
            } footer: {
                Text(L("settings.gesture_help", ["source": L("source.finder")]))
            }

            Section {
                Toggle(L("settings.login"), isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                    .disabled(!loginItem.isAvailable)
                if loginItem.needsApproval {
                    Text(L("settings.login_approval")).font(.callout).foregroundStyle(.orange)
                } else if !loginItem.isAvailable {
                    Text(L("settings.login_unavailable")).font(.callout).foregroundStyle(.secondary)
                }
                Picker(L("settings.language"), selection: languageSelection) {
                    Text(L("settings.language_system")).tag(Localization.systemPreference)
                    ForEach(Localization.languages, id: \.code) { Text($0.name).tag($0.code) }
                }
            }

            Section {
                ForEach(folderAccess.grants, id: \.self) { folder in
                    HStack {
                        Label(folder.path(percentEncoded: false), systemImage: "folder")
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button(L("folders.remove")) { folderAccess.remove(folder) }
                    }
                }
                if FolderAccessStore.isSandboxed {
                    Button(L("folders.allow_home")) {
                        _ = folderAccess.requestAccess(covering: [FolderAccessStore.homeFolder])
                    }
                }
            } header: {
                Text(L("folders.title"))
            } footer: {
                Text(L("folders.help"))
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .onAppear { loginItem.refresh() }
    }
}
