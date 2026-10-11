import CoreGraphics
import Foundation

@MainActor
struct DictationServices {
    let folders: FolderStore
    let history: HistoryStore
    let recordings: RecordingStore
    let microphones: any MicrophoneProviding
    let recorder: any RecordingProviding
    let keys: any APIKeyStoring
    let transcriber: any TranscriptionProviding
    let shortcuts: any GlobalShortcutProviding
    let inserter: any TextInsertionProviding
    /// Screen & System Audio Recording; nil (tests without a fake) counts as denied.
    var requestSystemAudioAccess: (() async -> Bool)? = nil
}

@MainActor
enum DictationRuntime {
    static func make(profile: RuntimeProfile) -> DictationModel {
        RuntimeFactory.make(profile: profile, production: {
            let history = HistoryStore()
            let keys = FileKeyStore()
            let services = DictationServices(
                folders: FolderStore(), history: history, recordings: RecordingStore(history: history),
                microphones: MicrophoneService(),
                recorder: RecordingService(makeMeetingDriver: { NativeMeetingCaptureDriver(microphoneID: $0, paths: $1, event: $2) }) { NativeCaptureDriver(microphoneID: $0, paths: $1, event: $2) },
                keys: keys, transcriber: MistralTranscriptionService(keys: keys),
                shortcuts: NativeGlobalShortcutService(),
                inserter: TextInsertionService(environment: NativeTextInsertionEnvironment()),
                requestSystemAudioAccess: { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() }
            )
            return DictationModel(profile: .production, services: services)
        }, testing: { DictationModel(profile: .testing) })
    }
}
