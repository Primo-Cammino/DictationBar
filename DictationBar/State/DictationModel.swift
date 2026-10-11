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
    private var browserOutputs: [BrowserAudioTarget] = []
    private var browserPolicy = BrowserSuggestionPolicy()
    private(set) var browserSuggestion: BrowserAudioTarget?
    @ObservationIgnored var onBrowserSuggestionChanged: ((BrowserAudioTarget?) -> Void)?
    var shortcut: DictationShortcut { configuration.shortcut ?? .default }
    var preferredMicrophone: Microphone? {
        MicrophoneRouting.preferred(microphones, configuredID: configuration.microphoneID,
                                    automaticBluetooth: configuration.preferBluetooth ?? true)
    }
    var sourceName: String {
        if activeToken?.origin == .browserRecording { return currentEntry?.sourceLabel ?? "Browser-Audio" }
        return microphones.first { $0.id == actualMicrophoneID }?.name ?? preferredMicrophone?.name ?? "Nicht gewählt"
    }
    var browserAvailabilityMessage: String? { services?.browserAudio?.availabilityMessage }
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
        phase = origin == .historyRetry ? .transcribing : .preparing
        session = origin != .historyRetry
            ? DictationSession(id: id, createdAt: now, configuration: configuration, token: token)
            : nil
        updateBrowserSuggestion()
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

    func requestQuit() { quitRequested = true; updateBrowserSuggestion() }
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
        updateBrowserSuggestion()
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
        services.shortcuts.onToggle = { [weak self] in self?.toggleRecording() }
        services.shortcuts.onEscape = { [weak self] in self?.stopRecording(reason: .normal) }
        if profile == .production {
            do { try services.shortcuts.configure(shortcut); try services.shortcuts.register() }
            catch { shortcutMessage = Self.userMessage(error) }
        }
        initialized = true
        services.browserAudio?.onOutputsChanged = { [weak self] outputs in
            self?.browserOutputs = outputs
            self?.updateBrowserSuggestion()
        }
        if profile == .production {
            services.microphones.startMonitoring()
            services.browserAudio?.start()
        }
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
        do {
            try services?.shortcuts.configure(value)
            if profile == .production { try services?.shortcuts.register() }
            configuration.shortcut = value
            shortcutMessage = nil
            await saveConfiguration()
        } catch { shortcutMessage = error.localizedDescription }
    }

    func setPreferBluetooth(_ value: Bool) async {
        configuration.preferBluetooth = value
        await saveConfiguration()
    }

    func setBrowserSuggestions(_ value: Bool) async {
        configuration.browserSuggestions = value
        updateBrowserSuggestion()
        await saveConfiguration()
    }

    private func updateBrowserSuggestion() {
        let target = browserPolicy.update(browserOutputs, enabled: configuration.browserSuggestions ?? true,
                                          busy: !canStart)
        guard target != browserSuggestion else { return }
        browserSuggestion = target
        onBrowserSuggestionChanged?(target)
    }

    func dismissBrowserSuggestion() {
        if let target = browserSuggestion { browserPolicy.dismiss(target) }
        updateBrowserSuggestion()
    }

    func recordSuggestedBrowser(_ target: BrowserAudioTarget) {
        guard canStart, browserSuggestion == target else { return }
        browserPolicy.dismiss(target)
        guard let token = begin(origin: .browserRecording) else { return }
        stopReason = nil
        operationTask = Task { await executeLive(token, browser: target) }
    }

    private func stopMonitoring() {
        services?.microphones.stopMonitoring()
        services?.browserAudio?.stop()
        services?.shortcuts.unregister()
        onBrowserSuggestionChanged?(nil)
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

    func requestInsertionPermission() { services?.inserter.requestPermission() }
    func requestMicrophonePermission() async -> Bool { await services?.microphones.requestAccess() == true }

    func toggleRecording() {
        if phase == .recording || phase == .preparing, isBusy {
            stopRecording(reason: .normal)
        } else if canStart, let token = begin(origin: .liveDictation) {
            stopReason = nil
            operationTask = Task { await executeLive(token) }
        }
    }

    func stopRecording(reason: RecordingStopReason) {
        guard isBusy, [.preparing, .recording, .saving].contains(phase) else { return }
        if reason == .quit || stopReason == nil || reason == .interrupted { stopReason = reason }
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

    private func executeLive(_ token: OperationToken, browser: BrowserAudioTarget? = nil) async {
        guard let services, let snapshot = session?.configuration else { finish(token: token); return }
        currentEntry = nil
        do {
            guard snapshot.folderBookmark != nil else { throw LocalStoreError.missingFolder }
            let microphoneID: String
            if let browser {
                guard await services.browserAudio?.requestCaptureAccess() == true else { throw BrowserCaptureAccessFailure.denied }
                microphoneID = "browser:" + browser.bundleID
            } else {
                guard await services.microphones.requestAccess() else { throw MicrophoneAccessFailure.denied }
                microphones = services.microphones.microphones()
                guard let microphone = MicrophoneRouting.preferred(microphones, configuredID: snapshot.microphoneID,
                                                automaticBluetooth: snapshot.preferBluetooth ?? true) else { throw CaptureFailure.deviceUnavailable }
                microphoneID = microphone.id
                actualMicrophoneID = microphoneID
            }
            guard isCurrent(token), !quitRequested else { await finishOperation(token); return }
            var entry = HistoryEntry(id: token.id, createdAt: session?.createdAt ?? Date(),
                                     microphoneID: microphoneID, folderBookmark: snapshot.folderBookmark!)
            entry.sourceLabel = browser.map { $0.name + " · Browser-Audio" }
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
            do { try services.shortcuts.setCaptureActive(true) }
            catch { shortcutMessage = Self.userMessage(error) }
            if let browser { try await services.recorder.startBrowser(browser, paths: paths) }
            else { try await services.recorder.start(microphoneID: microphoneID, paths: paths) }
            var visible = entry
            visible.status = .recording
            publish(visible)
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
        await finishOperation(token, error: detail)
    }

    private func finishOperation(_ token: OperationToken, error: String? = nil) async {
        guard isCurrent(token) else { return }
        let resultMessage = currentEntry?.transcript == nil
            ? (currentEntry?.duration == nil ? nil : "WAV gespeichert. Transkription ist über die History möglich.")
            : currentEntry?.insertion.title
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
        if error == nil { message = resultMessage }
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
        case let error as BrowserCaptureAccessFailure: error.localizedDescription
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

enum BrowserCaptureAccessFailure: LocalizedError {
    case denied
    var errorDescription: String? { "Browser-Aufnahme benötigt die macOS-Freigabe für Bildschirm- und Systemaudioaufnahme. Bitte DictationBar freigeben und erneut starten." }
}
