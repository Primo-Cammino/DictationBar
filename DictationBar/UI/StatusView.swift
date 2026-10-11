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
                LabeledContent(dictation.isMeeting ? "Meeting" : "Diktat", value: dictation.phase.title)
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

            let dictating = !dictation.isMeeting && (dictation.phase == .recording || dictation.phase == .preparing)
            HStack {
                Button(dictating ? "Diktat stoppen" : "Diktat starten") { dictation.toggleRecording() }
                    .disabled(!dictation.canStart && !dictating)
                Button(dictation.isMeeting ? "Meeting stoppen" : "Meeting starten") { dictation.toggleMeeting() }
                    .disabled(dictation.isMeeting ? dictation.phase != .recording : !dictation.canStart)
            }
            if !dictation.isMeeting {
                Text("\(dictation.shortcut.displayName): Diktat Start / Stop · Escape: Stop")
                    .font(.caption).foregroundStyle(.secondary)
            }

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
