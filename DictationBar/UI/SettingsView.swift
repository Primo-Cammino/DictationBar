import AppKit
import SwiftUI

@MainActor
struct SettingsView: View {
    let dictation: DictationModel
    let status: StatusModel
    @State private var key = ""
    @State private var savingKey = false

    var body: some View {
        Form {
            Section("Tastenkürzel") {
                ShortcutRecorder(shortcut: dictation.shortcut) { value in
                    Task { await dictation.configureShortcut(value) }
                }.disabled(dictation.isBusy)
                Text("Dasselbe Kürzel startet und stoppt das Diktat. Escape stoppt die Aufnahme.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = dictation.shortcutMessage { Text(message).foregroundStyle(.secondary) }
            }
            Section("Aufnahme") {
                Toggle("Bluetooth-Mikrofon automatisch bevorzugen", isOn: Binding(get: {
                    dictation.configuration.preferBluetooth ?? true
                }, set: { value in Task { await dictation.setPreferBluetooth(value) } }))
                LabeledContent("Aktuelle Quelle", value: dictation.sourceName)
                Picker("Mikrofon", selection: Binding(get: {
                    dictation.preferredMicrophone?.id ?? dictation.configuration.microphoneID ?? ""
                }, set: { id in Task { await dictation.setMicrophone(id.isEmpty ? nil : id) } })) {
                    Text("Bitte wählen").tag("")
                    ForEach(dictation.microphones) { microphone in
                        Text(microphone.name).tag(microphone.id)
                    }
                    if let id = dictation.configuration.microphoneID, !dictation.microphones.contains(where: { $0.id == id }) {
                        Text("Gewähltes Mikrofon nicht verfügbar").tag(id)
                    }
                }
                HStack {
                    Button("Mikrofone aktualisieren") { dictation.refreshMicrophones() }
                    Button("Mikrofon freigeben") {
                        Task { _ = await dictation.requestMicrophonePermission(); status.refresh() }
                    }
                }
                LabeledContent("WAV-Ordner") {
                    Text(dictation.folderName).lineLimit(2).truncationMode(.middle).help(dictation.folderName)
                }
                Button("Aufnahmeordner wählen …") { chooseFolder() }
                Text("Ordner und manuelle Auswahl gelten ab der nächsten Aufnahme. Bei automatischer Bluetooth-Auswahl wird auch eine laufende Aufnahme sofort auf das verbundene Headset umgestellt.").font(.caption).foregroundStyle(.secondary)
            }

            Section("Browser-Audio") {
                Toggle("Aufnahmehinweis bei Browser-Audio", isOn: Binding(get: {
                    dictation.configuration.browserSuggestions ?? true
                }, set: { value in Task { await dictation.setBrowserSuggestions(value) } }))
                Text("Der Hinweis startet keine Aufnahme. Erst „Aufnehmen“ erfasst den Ton des gewählten Browsers, einschließlich anderer Tabs. Die WAV bleibt lokal in der History; Transkription erfolgt nur auf Wunsch.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message = dictation.browserAvailabilityMessage { Text(message).foregroundStyle(.secondary) }
            }

            Section("Mistral Voxtral · eigener API-Key") {
                Text(dictation.keyStatus).font(.callout).foregroundStyle(.secondary)
                SecureField("Mistral-API-Key", text: $key)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Key speichern") {
                        let value = key
                        key = ""
                        savingKey = true
                        Task { await dictation.saveKey(value); savingKey = false }
                    }
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || savingKey)
                    Button("Key entfernen") { Task { await dictation.removeKey() } }.disabled(savingKey)
                    Button("Key bei Mistral prüfen") { Task { await dictation.verifyKey() } }.disabled(savingKey)
                }
                Text("Der Key liegt nur auf diesem Mac in „Application Support/DictationBar“, lesbar nur für deinen Benutzer. Für ein Diktat wird die gespeicherte WAV an Mistral gesendet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .task { await dictation.refreshKeyStatus() }

            Section("Automatisch einfügen") {
                Text(dictation.insertionPermissionSummary)
                    .font(.callout).foregroundStyle(.secondary)
                Button("Einfügen erlauben …") { dictation.requestInsertionPermission() }
                Text("Ohne geeignetes Eingabefeld bleibt der Text in der History. Nach dem Einfügen steht wieder dein vorheriger Inhalt in der Zwischenablage.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if let message = dictation.message {
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
        .frame(width: 560)
        .task { dictation.refreshMicrophones() }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Aufnahmeordner wählen"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await dictation.selectFolder(url) }
        }
    }
}
