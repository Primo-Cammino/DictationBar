import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class DictationModel {
    let profile: RuntimeProfile
    var configuration: AppConfiguration
    private(set) var phase: DictationPhase = .idle
    private(set) var session: DictationSession?
    private(set) var activeToken: OperationToken?
    private(set) var quitRequested = false
    private(set) var message: String?
    private(set) var actualMicrophoneID: String?
    private var requestedMicrophoneID: String?
    /// A meeting source that ended mid-recording; cleared when the meeting ends.
    /// The status panel shows it beside, never instead of, the current notice.
    private(set) var missingSource: MeetingMixer.Source?
    var isMeeting: Bool { activeToken?.origin == .meeting }
    /// Short message for the status panel; a newer one or a new activity replaces it.
    private(set) var notice: PanelNotice?
    private var meetingStartedAt: Date?

    /// What the status panel shows as running. Derived from the operation, not from
    /// `phase` alone, because a failed operation leaves `phase == .failed` behind.
    var panelActivity: PanelActivity? {
        guard let origin = activeToken?.origin else { return nil }
        switch (origin, phase) {
        case (.meeting, .preparing): return .meetingStarting
        case (.meeting, .recording): return .meeting(since: meetingStartedAt ?? Date())
        case (.meeting, _): return .meetingSaving
        case (.liveDictation, .preparing), (.liveDictation, .recording): return .dictation
        default: return .transcription
        }
    }
    var shortcut: DictationShortcut { configuration.shortcut ?? .default }
    var meetingShortcut: DictationShortcut { configuration.meetingShortcut ?? .meetingDefault }
    var preferredMicrophone: Microphone? {
        MicrophoneRouting.preferred(microphones, configuredID: configuration.microphoneID,
                                    automaticBluetooth: configuration.preferBluetooth ?? true)
    }
    var sourceName: String {
        microphones.first { $0.id == actualMicrophoneID }?.name ?? preferredMicrophone?.name ?? "Nicht gewählt"
    }
    private var generation: UInt64 = 0
    private var insertionAttempted = false
    private(set) var history: [HistoryEntry] = []
    private(set) var historyWarnings: [String] = []
    private(set) var microphones: [Microphone] = []
    private(set) var initialized = false
    private var initializationStarted = false
    private(set) var folderName = "Noch nicht gewählt"
    private(set) var keyStatus = "Noch nicht geprüft"
    private(set) var shortcutMessage: String?
    private(set) var meetingShortcutMessage: String?
    @ObservationIgnored private let services: DictationServices?
    @ObservationIgnored private var operationTask: Task<Void, Never>?
    @ObservationIgnored private var currentEntry: HistoryEntry?
    @ObservationIgnored private var stopReason: RecordingStopReason?
    @ObservationIgnored private var stopSignal: CheckedContinuation<RecordingStopReason, Never>?
    private enum Preservation { case audio(HistoryEntry), text(HistoryEntry) }
    @ObservationIgnored private var preservation: Preservation?
    @ObservationIgnored private var repairScheduled = false

    init(profile: RuntimeProfile, configuration: AppConfiguration = AppConfiguration(), services: DictationServices? = nil) {
        self.profile = profile
        self.configuration = configuration
        self.services = services
    }

    var isBusy: Bool { activeToken != nil }
    var canStart: Bool { initialized && !isBusy && !quitRequested && preservation == nil && services?.recorder.isActive != true }
    var needsPreservation: Bool { preservation != nil }
    var insertionPermitted: Bool { services?.inserter.isPermitted == true }
    var insertionPermissionSummary: String { services?.inserter.permissionSummary ?? "Einfügefreigabe nicht geprüft" }

    @discardableResult
    func begin(origin: OperationOrigin, id: UUID = UUID(), now: Date = Date()) -> OperationToken? {
        guard !isBusy, !quitRequested else { return nil }
        generation &+= 1
        let token = OperationToken(id: id, generation: generation, origin: origin)
        activeToken = token
        insertionAttempted = false
        message = nil
        notice = nil
        phase = origin == .historyRetry ? .transcribing : .preparing
        session = origin != .historyRetry
            ? DictationSession(id: id, createdAt: now, configuration: configuration, token: token)
            : nil
        return token
    }

    func isCurrent(_ token: OperationToken) -> Bool { activeToken == token }

    func transition(to phase: DictationPhase, token: OperationToken) {
        guard isCurrent(token) else { return }
        self.phase = phase
    }

    func claimInsertion(token: OperationToken) -> Bool {
        guard isCurrent(token), token.origin == .liveDictation,
              !quitRequested, !insertionAttempted else { return false }
        insertionAttempted = true
        return true
    }

    func requestQuit() { quitRequested = true }
    func refuseQuit(message: String) {
        quitRequested = false
        self.message = message
    }

    /// Call only after local work has finished; the gate stays held across await.
    func finish(token: OperationToken, error: String? = nil) {
        guard isCurrent(token) else { return }
        activeToken = nil
        session = nil
        message = error
        phase = error == nil ? .idle : .failed
        actualMicrophoneID = nil
        requestedMicrophoneID = nil
        missingSource = nil
    }

    func initialize() async {
        guard !initializationStarted else { return }
        initializationStarted = true
        // Hosted XCTest composition has no native services and no startup hooks.
        guard let services else { initialized = true; return }
        do {
            configuration = try await services.folders.load()
            await updateFolderName()
        } catch { message = "Einstellungen konnten nicht gelesen werden. Bitte erneut einrichten; das Original bleibt erhalten." }
        do {
            let snapshot = try await services.recordings.recover()
            history = snapshot.entries
            historyWarnings = snapshot.warnings
        } catch { historyWarnings = ["Die History konnte nicht geladen werden. Vorhandene Dateien bleiben erhalten."] }
        refreshMicrophones()
        services.microphones.onDevicesChanged = { [weak self] in self?.refreshMicrophones() }
        services.recorder.onMicrophoneChanged = { [weak self] id in
            guard let self, self.activeToken?.origin == .liveDictation else { return }
            self.actualMicrophoneID = id
            self.requestedMicrophoneID = nil
            self.routeLiveMicrophone()
        }
        services.recorder.onMicrophoneSwitchFailed = { [weak self] in
            self?.requestedMicrophoneID = nil
            self?.message = "Mikrofonwechsel fehlgeschlagen. Die bisherige Quelle bleibt aktiv, sofern sie verfügbar ist."
        }
        services.recorder.onInterruption = { [weak self] in self?.stopRecording(reason: .interrupted) }
        services.recorder.onSourceLost = { [weak self] source in
            guard let self, self.isMeeting else { return }
            if self.missingSource == nil { self.playCue(Self.warningCue) }
            self.missingSource = source
        }
        services.shortcuts.onToggle = { [weak self] in self?.toggleRecording() }
        services.shortcuts.onEscape = { [weak self] in self?.stopRecording(reason: .normal) }
        services.shortcuts.onMeeting = { [weak self] in self?.toggleMeeting() }
        if profile == .production {
            // Registered separately: a key held by another app must not block the other one.
            do { try services.shortcuts.configure(shortcut); try services.shortcuts.register() }
            catch { shortcutMessage = Self.userMessage(error) }
            do { try services.shortcuts.configureMeeting(meetingShortcut); try services.shortcuts.registerMeeting() }
            catch { meetingShortcutMessage = Self.userMessage(error) }
        }
        initialized = true
        if profile == .production { services.microphones.startMonitoring() }
    }

    func refreshMicrophones() {
        microphones = services?.microphones.microphones() ?? []
        routeLiveMicrophone()
    }

    private func routeLiveMicrophone() {
        guard activeToken?.origin == .liveDictation, phase == .recording, !quitRequested,
              let snapshot = session?.configuration, snapshot.preferBluetooth ?? true,
              let target = MicrophoneRouting.preferred(microphones, configuredID: snapshot.microphoneID, automaticBluetooth: true),
              target.isBluetooth, target.id != actualMicrophoneID, requestedMicrophoneID == nil else { return }
        requestedMicrophoneID = target.id
        services?.recorder.switchMicrophone(to: target.id)
    }

    func configureShortcut(_ value: DictationShortcut) async {
        guard !isBusy else { return }
        guard value != meetingShortcut else {
            shortcutMessage = "Das Diktat-Kürzel muss sich vom Meeting-Kürzel unterscheiden."
            return
        }
        do {
            try services?.shortcuts.configure(value)
            if profile == .production { try services?.shortcuts.register() }
            configuration.shortcut = value
            shortcutMessage = nil
            await saveConfiguration()
        } catch { shortcutMessage = error.localizedDescription }
    }

    func configureMeetingShortcut(_ value: DictationShortcut) async {
        guard !isBusy else { return }
        guard value != shortcut else {
            meetingShortcutMessage = "Das Meeting-Kürzel muss sich vom Diktat-Kürzel unterscheiden."
            return
        }
        do {
            try services?.shortcuts.configureMeeting(value)
            if profile == .production { try services?.shortcuts.registerMeeting() }
            configuration.meetingShortcut = value
            meetingShortcutMessage = nil
            await saveConfiguration()
        } catch { meetingShortcutMessage = error.localizedDescription }
    }

    func setPreferBluetooth(_ value: Bool) async {
        configuration.preferBluetooth = value
        await saveConfiguration()
    }

    private func stopMonitoring() {
        services?.microphones.stopMonitoring()
        services?.shortcuts.unregister()
    }

    func setMicrophone(_ id: String?) async {
        configuration.microphoneID = id
        await saveConfiguration()
    }

    func selectFolder(_ url: URL) async {
        do {
            let bookmark = try await services?.folders.makeBookmark(for: url)
            configuration.folderBookmark = bookmark
            await saveConfiguration()
            await updateFolderName()
        } catch { message = Self.userMessage(error) }
    }

    func refreshKeyStatus() async {
        do { keyStatus = try await services?.keys.hasKey() == true ? "Lokal gespeichert" : "Nicht hinterlegt" }
        catch { keyStatus = Self.userMessage(error) }
    }

    func verifyKey() async {
        guard let services else { return }
        keyStatus = "Prüfe bei Mistral …"
        do {
            let status = try await services.transcriber.verifyKey()
            keyStatus = switch status {
            case 200..<300: "Key gültig – Mistral antwortet mit \(status)."
            case 401, 403: "Key ungültig – Mistral antwortet mit \(status)."
            default: "Mistral antwortet mit \(status); Key nicht bestätigt."
            }
        } catch { keyStatus = Self.userMessage(error) }
    }

    func saveKey(_ key: String) async {
        do { try await services?.keys.save(key); await refreshKeyStatus(); message = "Mistral-Key gespeichert." }
        catch { message = Self.userMessage(error) }
    }

    func removeKey() async {
        do { try await services?.keys.remove(); await refreshKeyStatus(); message = "Mistral-Key entfernt." }
        catch { message = Self.userMessage(error) }
    }

    /// Start/stop feedback with macOS system sounds; silent in tests.
    // ponytail: fixed sounds and volume, add a setting if someone wants them off or different.
    private func playCue(_ name: String) {
        guard profile == .production, let sound = NSSound(named: name) else { return }
        sound.volume = 0.5
        sound.play()
    }
    private static let warningCue = "Basso"

    private func post(_ kind: PanelNotice.Kind, _ text: String, entry: HistoryEntry? = nil) {
        let notice = PanelNotice(kind: kind, text: text, entry: entry)
        self.notice = notice
        if kind == .interrupted { playCue(Self.warningCue) }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(notice.seconds))
            // An older timer never hides a newer notice.
            if self?.notice?.id == notice.id { self?.notice = nil }
        }
    }

    func requestInsertionPermission() { services?.inserter.requestPermission() }
    func requestMicrophonePermission() async -> Bool { await services?.microphones.requestAccess() == true }

    func toggleRecording() {
        if isMeeting {
            message = "Meeting läuft. Diktat ist währenddessen gesperrt."
            post(.info, "Meeting läuft")
        } else if phase == .recording || phase == .preparing, isBusy {
            stopRecording(reason: .normal)
        } else if canStart, let token = begin(origin: .liveDictation) {
            stopReason = nil
            operationTask = Task { await executeLive(token) }
        }
    }

    /// Starts a meeting only when nothing else runs and stops only a recording
    /// meeting; a stop while it is still preparing is ignored.
    func toggleMeeting() {
        if isMeeting {
            if phase == .recording { stopRecording(reason: .normal) }
        } else if let refusal = meetingRefusal {
            message = refusal
            post(.info, refusal)
        } else if let token = begin(origin: .meeting) {
            stopReason = nil
            operationTask = Task { await executeLive(token) }
        }
    }

    private var meetingRefusal: String? {
        let reason: String? = if !initialized { "Die App startet noch." }
            else if quitRequested { "Die App wird beendet." }
            else if isBusy {
                activeToken?.origin == .liveDictation && [.preparing, .recording].contains(phase)
                    ? "Ein Diktat läuft." : "Eine Transkription läuft."
            }
            else if preservation != nil { "Eine Aufnahme ist noch nicht gesichert. Bitte zuerst die lokale Sicherung wiederholen." }
            else if services?.recorder.isActive == true { CaptureFailure.busy.localizedDescription }
            else { nil }
        return reason.map { "Kein Meeting: " + $0 }
    }

    func stopRecording(reason: RecordingStopReason) {
        guard isBusy, [.preparing, .recording, .saving].contains(phase) else { return }
        if stopReason.map({ reason.priority > $0.priority }) ?? true { stopReason = reason }
        if let stopSignal {
            self.stopSignal = nil
            stopSignal.resume(returning: stopReason ?? reason)
        }
    }

    func retry(_ id: UUID) {
        guard canStart, let entry = history.first(where: { $0.id == id }), entry.transcript == nil,
              !entry.isMeeting, let token = begin(origin: .historyRetry, id: id) else { return }
        operationTask = Task {
            guard let services else { finish(token: token); return }
            do {
                try await services.history.authorizeExisting(token)
                try await transcribe(entry, token: token)
                await finishOperation(token)
            } catch { await failOperation(token, error: error) }
        }
    }

    @discardableResult
    func repairPreservation() -> Task<Void, Never>? {
        guard !isBusy, !repairScheduled, services?.recorder.isActive != true, preservation != nil else { return nil }
        repairScheduled = true
        let task = Task { await repairCheckpoint(); repairScheduled = false }
        operationTask = task
        return task
    }

    /// All ordinary termination paths call this method. It waits for local work,
    /// but invalidates an outstanding HTTP request without waiting for its answer.
    func terminateSafely() async -> Bool {
        requestQuit()
        guard let services else { return true }
        if phase == .transcribing, let token = activeToken {
            operationTask?.cancel()
            Task { await services.transcriber.cancel() }
            await services.history.revoke(token)
            finish(token: token)
            stopMonitoring()
            return true
        }
        if phase == .preparing, currentEntry == nil, let token = activeToken {
            operationTask?.cancel()
            finish(token: token)
            stopMonitoring()
            return true
        }
        if isBusy {
            stopRecording(reason: .quit)
            await operationTask?.value
        }
        if services.recorder.isActive {
            refuseQuit(message: CaptureFailure.timeout.localizedDescription)
            return false
        }
        if preservation != nil { await repairCheckpoint() }
        guard preservation == nil, !isBusy else {
            refuseQuit(message: "Die lokale Sicherung ist fehlgeschlagen. Die App bleibt offen; bitte die Sicherung wiederholen.")
            return false
        }
        stopMonitoring()
        return true
    }

    private func executeLive(_ token: OperationToken) async {
        guard let services, let snapshot = session?.configuration else { finish(token: token); return }
        let meeting = token.origin == .meeting
        currentEntry = nil
        do {
            guard snapshot.folderBookmark != nil else { throw LocalStoreError.missingFolder }
            if meeting {
                guard await services.requestSystemAudioAccess?() == true else { throw SystemAudioAccessFailure.denied }
            }
            guard await services.microphones.requestAccess() else { throw MicrophoneAccessFailure.denied }
            microphones = services.microphones.microphones()
            guard let microphone = MicrophoneRouting.preferred(microphones, configuredID: snapshot.microphoneID,
                                            automaticBluetooth: snapshot.preferBluetooth ?? true) else { throw CaptureFailure.deviceUnavailable }
            let microphoneID = microphone.id
            actualMicrophoneID = microphoneID
            guard isCurrent(token), !quitRequested else { await finishOperation(token); return }
            var entry = HistoryEntry(id: token.id, createdAt: session?.createdAt ?? Date(), microphoneID: microphoneID,
                                     folderBookmark: snapshot.folderBookmark!, kind: meeting ? .meeting : nil)
            currentEntry = entry
            let paths = try await services.recordings.prepare(entry, token: token)
            guard isCurrent(token) else { return }
            entry.stagingOwned = true
            currentEntry = entry
            publish(entry)
            if quitRequested {
                var aborted = entry
                aborted.status = .failed
                aborted.message = "Aufnahme vor dem Start beendet. Es wurde kein Audio aufgenommen."
                try await services.history.save(aborted, token: token)
                await finishOperation(token)
                return
            }
            preservation = .audio(entry)
            // Escape stays free during meetings, e.g. to leave full screen in Zoom.
            if !meeting {
                do { try services.shortcuts.setCaptureActive(true) }
                catch { shortcutMessage = Self.userMessage(error) }
            }
            if meeting { try await services.recorder.startMeeting(microphoneID: microphoneID, paths: paths) }
            else { try await services.recorder.start(microphoneID: microphoneID, paths: paths) }
            var visible = entry
            visible.status = .recording
            publish(visible)
            meetingStartedAt = Date()
            transition(to: .recording, token: token)
            playCue("Tink")
            routeLiveMicrophone()
            let reason = await waitForStop()
            playCue("Bottle")
            try? services.shortcuts.setCaptureActive(false)
            transition(to: .saving, token: token)
            let completion = try await services.recorder.stop()
            let saved = try await services.recordings.finalize(entry, token: token,
                            interrupted: completion.interrupted || reason != .normal || quitRequested)
            preservation = nil
            currentEntry = saved
            publish(saved)
            if token.origin == .liveDictation, !quitRequested, reason == .normal, !completion.interrupted {
                try await transcribe(saved, token: token)
            }
            await finishOperation(token)
        } catch {
            try? services.shortcuts.setCaptureActive(false)
            // Only confirmed shutdown permits conversion of an impossible audio
            // checkpoint into failed metadata. IO/collision failures retain audio.
            if case .audio(let entry) = preservation, !services.recorder.isActive {
                if (error as? LocalStoreError) == .invalidWAV {
                    try? await saveFailedAudioCheckpoint(entry, token: token)
                } else if phase == .preparing {
                    do {
                        currentEntry = try await services.recordings.completeCheckpoint(entry, token: token)
                        preservation = nil
                    } catch {
                        if (error as? LocalStoreError) == .invalidWAV {
                            try? await saveFailedAudioCheckpoint(entry, token: token)
                        } else {
                            await finishOperation(token, error: Self.userMessage(error))
                            return
                        }
                    }
                }
            }
            await failOperation(token, error: error)
        }
    }

    private func waitForStop() async -> RecordingStopReason {
        if quitRequested { return .quit }
        if let stopReason { return stopReason }
        return await withCheckedContinuation { stopSignal = $0 }
    }

    private func transcribe(_ original: HistoryEntry, token: OperationToken) async throws {
        guard let services, isCurrent(token), !quitRequested else { return }
        var entry = original
        currentEntry = entry
        entry.status = .transcribing
        transition(to: .saving, token: token)
        try await services.history.save(entry, token: token)
        publish(entry)
        let file = try await services.recordings.readableWAV(for: entry)
        guard isCurrent(token), !quitRequested else { return }
        transition(to: .transcribing, token: token)
        let text = try await services.transcriber.transcribe(file: file)
        guard isCurrent(token), !quitRequested else { return }
        entry.transcript = text
        entry.status = .complete
        entry.message = nil
        entry.insertion = token.origin == .historyRetry ? .historyOnly : .notAttempted
        transition(to: .persisting, token: token)
        preservation = .text(entry)
        try await services.history.save(entry, token: token)
        preservation = nil
        currentEntry = entry
        publish(entry)
        if claimInsertion(token: token) {
            transition(to: .inserting, token: token)
            entry.insertion = await services.inserter.insert(text) { [weak self] in
                self?.isCurrent(token) == true && self?.quitRequested == false
            }
            preservation = .text(entry)
            try await services.history.save(entry, token: token)
            preservation = nil
        }
        currentEntry = entry
        publish(entry)
    }

    private func failOperation(_ token: OperationToken, error: Error) async {
        guard isCurrent(token) else { return }
        let detail = Self.userMessage(error)
        if var entry = currentEntry, preservation == nil, let services, await services.history.canWrite(token) {
            entry.status = entry.transcript == nil ? .failed : .complete
            entry.message = detail
            if (try? await services.history.save(entry, token: token)) == nil {
                // The WAV checkpoint already exists; this retains the pending
                // local metadata correction without claiming it was committed.
                preservation = .text(entry)
            }
        }
        await finishOperation(token, error: detail, errorKind: error is SystemAudioAccessFailure ? .permission : .error)
    }

    private func finishOperation(_ token: OperationToken, error: String? = nil,
                                 errorKind: PanelNotice.Kind = .error) async {
        guard isCurrent(token) else { return }
        let meetingEntry = currentEntry.flatMap { $0.isMeeting && $0.duration != nil ? $0 : nil }
        let resultMessage: String? = if let entry = meetingEntry {
            entry.status == .interrupted ? "Meeting unterbrochen. Die Aufnahme bis dahin ist gespeichert." : "Meeting gespeichert."
        } else if currentEntry?.transcript == nil {
            currentEntry?.duration == nil ? nil : "WAV gespeichert. Transkription ist über die History möglich."
        } else {
            currentEntry?.insertion.title
        }
        if let services {
            await services.history.revoke(token)
            if let snapshot = try? await services.history.load(), isCurrent(token) {
                history = snapshot.entries
                historyWarnings = snapshot.warnings
            }
        }
        guard isCurrent(token) else { return }
        currentEntry = nil
        finish(token: token, error: error)
        if let error {
            post(errorKind, error)
        } else {
            message = resultMessage
            if let entry = meetingEntry, let resultMessage, !quitRequested {
                post(entry.status == .interrupted ? .interrupted : .saved, resultMessage, entry: entry)
            }
        }
    }

    private func repairCheckpoint() async {
        guard let preservation, let services, !isBusy, !services.recorder.isActive else { return }
        let entry: HistoryEntry
        switch preservation { case .audio(let value), .text(let value): entry = value }
        generation &+= 1
        let token = OperationToken(id: entry.id, generation: generation, origin: .historyRetry)
        activeToken = token
        phase = .saving
        do {
            try await services.history.authorizeExisting(token)
            switch preservation {
            case .audio: _ = try await services.recordings.completeCheckpoint(entry, token: token)
            case .text: try await services.history.save(entry, token: token)
            }
            self.preservation = nil
            await finishOperation(token)
        } catch {
            var failure = error
            if case .audio(let original) = self.preservation, !services.recorder.isActive,
               (error as? LocalStoreError) == .invalidWAV {
                do { try await saveFailedAudioCheckpoint(original, token: token) }
                catch { failure = error }
            }
            await finishOperation(token, error: Self.userMessage(failure))
        }
    }

    /// Keep the original audio untouched. If metadata cannot be committed, only
    /// that write remains to repair; validation of irreparable audio is not retried.
    private func saveFailedAudioCheckpoint(_ original: HistoryEntry, token: OperationToken) async throws {
        guard let services, !services.recorder.isActive else { throw CaptureFailure.busy }
        var entry = original
        entry.status = .failed
        entry.message = LocalStoreError.invalidWAV.localizedDescription
        currentEntry = entry
        preservation = .text(entry)
        try await services.history.save(entry, token: token)
        preservation = nil
    }

    private func saveConfiguration() async {
        do { try await services?.folders.save(configuration) }
        catch { message = "Einstellungen konnten nicht gespeichert werden. Die bisherige Datei bleibt erhalten." }
    }

    private func publish(_ entry: HistoryEntry) {
        history.removeAll { $0.id == entry.id }
        history.append(entry)
        history.sort { $0.createdAt > $1.createdAt }
    }

    private func updateFolderName() async {
        guard let services else { return }
        do { folderName = try await services.folders.resolvedFolder(configuration.folderBookmark).url.path }
        catch { folderName = configuration.folderBookmark == nil ? "Noch nicht gewählt" : "Nicht erreichbar – bitte erneut wählen" }
    }

    private static func userMessage(_ error: Error) -> String {
        switch error {
        case let error as LocalStoreError: error.localizedDescription
        case let error as CaptureFailure: error.localizedDescription
        case let error as APIKeyFailure: error.localizedDescription
        case let error as TranscriptionFailure: error.localizedDescription
        case let error as MicrophoneAccessFailure: error.localizedDescription
        case let error as SystemAudioAccessFailure: error.localizedDescription
        case let error as ShortcutFailure: error.localizedDescription
        case is CancellationError: "Vorgang abgebrochen. Vorhandene Dateien bleiben erhalten."
        default: "Lokaler Speicherfehler. Vorhandene Dateien bleiben erhalten; bitte den Aufnahmeordner prüfen."
        }
    }
}

enum MicrophoneAccessFailure: LocalizedError {
    case denied
    var errorDescription: String? { "Mikrofonzugriff fehlt. Bitte DictationBar in den macOS-Datenschutzeinstellungen freigeben." }
}

enum SystemAudioAccessFailure: LocalizedError {
    case denied
    var errorDescription: String? { "Meetings brauchen die Freigabe unter Systemeinstellungen › Datenschutz & Sicherheit › Bildschirm- & Systemaudioaufnahme. Bitte DictationBar dort erlauben und die App neu starten." }
}
