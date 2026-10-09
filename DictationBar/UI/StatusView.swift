import AppKit
import SwiftUI

@MainActor
struct StatusView: View {
    let model: StatusModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("DictationBar")
                .font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Mikrofon", value: model.permissions.microphone.title)
                LabeledContent("Systemaudio", value: model.permissions.systemAudio.title)
                LabeledContent("Aufnahme", value: model.recordingAvailability.title)
            }
            .foregroundStyle(.secondary)

            Divider()

            HStack {
                Button("Status aktualisieren") {
                    model.refresh()
                }

                Spacer()

                Button("Beenden") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q")
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
