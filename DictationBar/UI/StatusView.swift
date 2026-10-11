import AppKit
import SwiftUI

@MainActor
struct StatusView: View {
    let model: StatusModel
    let dictation: DictationModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DictationBar")
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Mikrofon", value: model.permissions.microphone.title)
                LabeledContent("Systemaudio", value: model.permissions.systemAudio.title)
                LabeledContent(dictation.activeToken?.origin == .browserRecording ? "Browseraufnahme" : "Diktat", value: dictation.phase.title)
                LabeledContent("Quelle", value: dictation.sourceName)
                Text(dictation.insertionPermissionSummary).font(.caption)
            }
            .foregroundStyle(.secondary)

            if let message = dictation.message {
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let message = dictation.shortcutMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            Button(dictation.phase == .recording || dictation.phase == .preparing ? "Aufnahme stoppen" : "Aufnahme starten") {
                dictation.toggleRecording()
            }
            .disabled(!dictation.canStart && dictation.phase != .recording && dictation.phase != .preparing)
            Text("\(dictation.shortcut.displayName): Start / Stop · Escape: Stop")
                .font(.caption).foregroundStyle(.secondary)
            // ponytail: temporary U8 test button, removed in U9.
            Button("Meeting testen (vorläufig)") { dictation.startMeetingPreview() }
                .disabled(!dictation.canStart)

            if dictation.needsPreservation {
                Button("Lokale Sicherung wiederholen") { dictation.repairPreservation() }.disabled(dictation.isBusy)
            }

            HStack {
                Button("Einstellungen …") { openWindow(id: "settings"); NSApplication.shared.activate(ignoringOtherApps: true) }
                Button("History …") { openWindow(id: "history"); NSApplication.shared.activate(ignoringOtherApps: true) }
            }

            Divider()

            HStack {
                Button("Status aktualisieren") {
                    model.refresh()
                    dictation.refreshMicrophones()
                }

                Spacer()

                Button("Beenden") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 380)
    }
}
