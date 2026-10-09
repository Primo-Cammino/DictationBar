import SwiftUI

@main
@MainActor
struct DictationBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: StatusModel
    @State private var dictation: DictationModel

    init() {
        let profile = RuntimeProfile.resolve(environment: ProcessInfo.processInfo.environment)
        let runtime = DictationRuntime.make(profile: profile)
        _dictation = State(initialValue: runtime)
        _model = State(initialValue: StatusModel(
            permissionReader: RuntimeFactory.make(profile: profile,
                production: { NativePermissionReader() as any PermissionReading },
                testing: { TestingPermissionReader() as any PermissionReading }),
            audioAvailabilityService: UnavailableAudioService()
        ))
        AppDelegate.model = runtime
    }

    var body: some Scene {
        // SceneBuilder only allows `if #available`, so the main window is unconditional.
        // ponytail: hosted tests also open it; harmless, suppress via AppDelegate if it gets in the way.
        WindowGroup("DictationBar", id: "main") {
            StatusView(model: model, dictation: dictation)
        }
        .windowResizability(.contentSize)
        .commands { DictationCommands() }

        MenuBarExtra("DictationBar", systemImage: dictation.phase == .recording ? "record.circle" : "waveform") {
            StatusView(model: model, dictation: dictation)
        }
        .menuBarExtraStyle(.window)

        Window("DictationBar – Einstellungen", id: "settings") {
            SettingsView(dictation: dictation, status: model)
        }
        .windowResizability(.contentSize)

        Window("DictationBar – History", id: "history") {
            HistoryView(dictation: dictation)
        }
        .defaultSize(width: 680, height: 520)
    }
}

@MainActor
private struct DictationCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Einstellungen …") { show("settings") }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Button("DictationBar öffnen") { show("main") }
            Button("History …") { show("history") }
        }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
private struct TestingPermissionReader: PermissionReading {
    func snapshot() -> PermissionSnapshot { PermissionSnapshot(microphone: .notDetermined, systemAudio: .notVerified) }
}
