import XCTest
@testable import DictationBar

@MainActor
final class PipelineFixture {
    let files: LocalStoreFixture
    let model: DictationModel
    let history: HistoryStore
    let recorder = PipelineRecorder()
    let microphone = PipelineMicrophone()
    let transcriber = PipelineTranscriber()
    let inserter = PipelineInserter()
    let shortcuts = PipelineShortcuts()
    let systemAudio = PipelineSystemAudio()

    /// `existing` entries are journaled with a valid WAV before the model starts.
    init(profile: RuntimeProfile = .testing, shortcutRegistrationFails: Bool = false,
         meetingRegistrationFails: Bool = false,
         beforeWrite: @escaping () throws -> Void = {},
         existing: (LocalStoreFixture) throws -> [HistoryEntry] = { _ in [] }) async throws {
        files = try LocalStoreFixture()
        history = HistoryStore(supportURL: files.support, beforeWrite: beforeWrite)
        for entry in try existing(files) {
            let token = files.token(entry)
            await history.authorize(token); try await history.create(entry, token: token); await history.revoke(token)
            try LocalStoreFixture.wav().write(to: files.folder.appendingPathComponent(entry.filename))
        }
        let folders = FolderStore(supportURL: files.support)
        try await folders.save(AppConfiguration(microphoneID: "selected", folderBookmark: FolderStore.bookmark(for: files.folder)))
        let services = DictationServices(folders: folders, history: history, recordings: RecordingStore(history: history),
            microphones: microphone, recorder: recorder, keys: TestKeyStore(), transcriber: transcriber,
            shortcuts: shortcuts, inserter: inserter,
            requestSystemAudioAccess: { [systemAudio] in systemAudio.request() })
        shortcuts.registrationFails = shortcutRegistrationFails
        shortcuts.meetingRegistrationFails = meetingRegistrationFails
        model = DictationModel(profile: profile, services: services)
        await model.initialize()
        inserter.beforeInsert = { [history] in
            let saved = try? await history.load().entries.first
            return saved?.transcript != nil
        }
    }

    func wait(_ condition: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 4
        while !condition() {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                throw NSError(domain: "PipelineTestTimeout", code: 1)
            }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    func start() async throws { model.toggleRecording(); try await wait { model.phase == .recording } }
    func stop() { model.toggleRecording() }
    func startMeeting() async throws { model.toggleMeeting(); try await wait { model.phase == .recording } }
}

@MainActor
final class PipelineMicrophone: MicrophoneProviding {
    var onDevicesChanged: (() -> Void)?
    var devices = [Microphone(id: "selected", name: "Test microphone")]
    var granted = true
    var holdPermission = false
    var requests = 0
    var permission: CheckedContinuation<Bool, Never>?
    func microphones() -> [Microphone] { devices }
    func requestAccess() async -> Bool {
        requests += 1
        if holdPermission { return await withCheckedContinuation { permission = $0 } }
        return granted
    }
    func grant() { permission?.resume(returning: true); permission = nil }
}

@MainActor
final class PipelineRecorder: RecordingProviding {
    var isActive = false
    var onInterruption: (() -> Void)?
    var onMicrophoneChanged: ((String) -> Void)?
    var onMicrophoneSwitchFailed: (() -> Void)?
    var onSourceLost: ((MeetingMixer.Source) -> Void)?
    var switchFails = false
    var switches: [String] = []
    func switchMicrophone(to id: String) {
        switches.append(id)
        if switchFails { onMicrophoneSwitchFailed?(); return }
        device = id; onMicrophoneChanged?(id)
    }
    var meetingStarts = 0
    func startMeeting(microphoneID: String, paths: RecordingPaths) async throws {
        meetingStarts += 1
        try await start(microphoneID: microphoneID, paths: paths)
    }
    var starts = 0
    var stops = 0
    var startFailure: CaptureFailure?
    var confirmsShutdownOnStartFailure = false
    var beforeStartFailure: (() throws -> Void)?
    var holdStart = false
    var holdStop = false
    var startWaiter: CheckedContinuation<Void, Never>?
    var stopWaiter: CheckedContinuation<Void, Never>?
    var device: String?
    var audio = LocalStoreFixture.wav()
    var interrupted = false

    func start(microphoneID: String, paths: RecordingPaths) async throws {
        starts += 1; isActive = true; device = microphoneID
        try audio.write(to: paths.staging)
        if let startFailure {
            try beforeStartFailure?()
            if confirmsShutdownOnStartFailure { isActive = false }
            throw startFailure
        }
        if holdStart { await withCheckedContinuation { startWaiter = $0 } }
    }
    func stop() async throws -> CaptureCompletion {
        stops += 1
        if holdStop { await withCheckedContinuation { stopWaiter = $0 } }
        isActive = false
        return CaptureCompletion(interrupted: interrupted)
    }
    func confirmLateShutdown() { isActive = false; onInterruption?() }
    func releaseStart() { startWaiter?.resume(); startWaiter = nil }
    func releaseStop() { stopWaiter?.resume(); stopWaiter = nil }
}

@MainActor
final class PipelineTranscriber: TranscriptionProviding {
    var calls = 0
    var cancellations = 0
    var hold = false
    var failure: TranscriptionFailure?
    var response: CheckedContinuation<String, Error>?
    func transcribe(file: URL) async throws -> String {
        _ = try WAVValidator.inspect(file)
        calls += 1
        if let failure { throw failure }
        if hold { return try await withCheckedThrowingContinuation { response = $0 } }
        return "Neutraler Testtext."
    }
    func verifyKey() -> Int { 200 }
    func cancel() { cancellations += 1 }
    func release() { response?.resume(returning: "Neutraler Testtext."); response = nil }
}

@MainActor
final class PipelineInserter: TextInsertionProviding {
    var isPermitted = true
    var calls = 0
    var persistedBeforePaste = false
    var hold = false
    var waiter: CheckedContinuation<Void, Never>?
    var beforeInsert: (() async -> Bool)?
    func requestPermission() { }
    func insert(_ text: String, isCurrent: @escaping @MainActor () -> Bool) async -> InsertionStatus {
        persistedBeforePaste = await beforeInsert?() == true
        if hold { await withCheckedContinuation { waiter = $0 } }
        guard isCurrent() else { return .unavailable }
        calls += 1
        return .confirmed
    }
    func release() { waiter?.resume(); waiter = nil }
}

@MainActor
final class PipelineShortcuts: GlobalShortcutProviding {
    var onToggle: (() -> Void)?
    var onEscape: (() -> Void)?
    var onMeeting: (() -> Void)?
    var registrations = 0
    var meetingRegistrations = 0
    var escapeActive = false
    var registrationFails = false
    var meetingRegistrationFails = false
    var configuredShortcut = DictationShortcut.default
    var configuredMeetingShortcut: DictationShortcut?
    func configure(_ shortcut: DictationShortcut) throws { configuredShortcut = shortcut }
    func register() throws {
        registrations += 1
        if registrationFails { throw ShortcutFailure.registration }
    }
    func configureMeeting(_ shortcut: DictationShortcut) throws { configuredMeetingShortcut = shortcut }
    func registerMeeting() throws {
        meetingRegistrations += 1
        if meetingRegistrationFails { throw ShortcutFailure.registration }
    }
    func setCaptureActive(_ active: Bool) { escapeActive = active }
    func unregister() { escapeActive = false }
}

@MainActor
final class PipelineSystemAudio {
    var requests = 0
    var granted = true
    func request() -> Bool { requests += 1; return granted }
}
