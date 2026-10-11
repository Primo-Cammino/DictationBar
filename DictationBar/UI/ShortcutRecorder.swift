import AppKit
import Carbon
import SwiftUI

@MainActor
struct ShortcutRecorder: View {
    let title: String
    let shortcut: DictationShortcut
    let onSelect: (DictationShortcut) -> Void
    @State private var editing = false
    @State private var monitor: Any?
    @State private var resignObserver: NSObjectProtocol?
    @State private var hint = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent(title, value: shortcut.displayName)
            HStack {
                Button(editing ? "Tastenkürzel drücken …" : "Tastenkürzel ändern") { startEditing() }
                    .disabled(editing)
                if editing { Button("Abbrechen") { stopEditing() } }
            }
            if editing {
                Text(hint.isEmpty ? "Taste zusammen mit ⌥, ⌃ oder ⌘ drücken. Escape bricht ab." : hint)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stopEditing() }
    }

    private func startEditing() {
        guard !editing, let window = NSApp.keyWindow else { return }
        editing = true
        hint = ""
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                                                object: window, queue: .main) { _ in
            MainActor.assumeIsolated { stopEditing() }
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let consumed = MainActor.assumeIsolated {
                guard editing, event.window === window else { return false }
                if event.keyCode == UInt16(kVK_Escape) {
                    stopEditing()
                } else if let selected = DictationShortcut.capture(event) {
                    stopEditing()
                    onSelect(selected)
                } else if !event.isARepeat {
                    hint = "Bitte eine Taste zusammen mit ⌥, ⌃ oder ⌘ drücken."
                }
                return true
            }
            return consumed ? nil : event
        }
    }

    private func stopEditing() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        monitor = nil
        resignObserver = nil
        editing = false
        hint = ""
    }
}
