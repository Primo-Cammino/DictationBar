import Foundation

enum CaptureFailure: LocalizedError {
    case deviceUnavailable, configuration, start, timeout, busy

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable: "Das gewählte Mikrofon ist nicht verfügbar. Bitte erneut auswählen."
        case .configuration: "Das gewählte Mikrofon kann nicht im benötigten Audioformat aufnehmen."
        case .start: "Die Aufnahme konnte nicht gestartet werden. Vorhandene Dateien bleiben erhalten."
        case .timeout: "Die Aufnahme antwortet nicht. Dateien bleiben erhalten; ein neuer Start wartet auf ihre Stilllegung."
        case .busy: "Die vorherige Aufnahme ist noch nicht vollständig beendet."
        }
    }
}

struct CaptureCompletion: Equatable {
    let interrupted: Bool
}

enum CaptureEvent {
    case started
    case finished(CaptureCompletion)
    case failedToStart
    case microphoneChanged(String)
    case microphoneSwitchFailed
    /// One meeting source ended; the recording continues with the other.
    case sourceLost(MeetingMixer.Source)
}

protocol CaptureDriving: AnyObject {
    func start()
    func stop()
    func switchMicrophone(to id: String)
}

extension CaptureDriving {
    func switchMicrophone(to id: String) { }
}

@MainActor
protocol RecordingProviding: AnyObject {
    var isActive: Bool { get }
    var onInterruption: (() -> Void)? { get set }
    var onMicrophoneChanged: ((String) -> Void)? { get set }
    var onMicrophoneSwitchFailed: (() -> Void)? { get set }
    var onSourceLost: ((MeetingMixer.Source) -> Void)? { get set }
    func switchMicrophone(to id: String)
    /// System audio of all apps plus `microphoneID`, mixed into one WAV.
    func startMeeting(microphoneID: String, paths: RecordingPaths) async throws
    func start(microphoneID: String, paths: RecordingPaths) async throws
    func stop() async throws -> CaptureCompletion
}

extension RecordingProviding {
    var onMicrophoneChanged: ((String) -> Void)? { get { nil } set { } }
    var onMicrophoneSwitchFailed: (() -> Void)? { get { nil } set { } }
    var onSourceLost: ((MeetingMixer.Source) -> Void)? { get { nil } set { } }
    func switchMicrophone(to id: String) { }
    func startMeeting(microphoneID: String, paths: RecordingPaths) async throws { throw CaptureFailure.configuration }
}

/// The driver owns AVFoundation on a serial queue; this boundary owns callbacks,
/// deadlines and awaiters on MainActor. A deadline never claims driver shutdown.
@MainActor
final class RecordingService: RecordingProviding {
    typealias DriverFactory = (String, RecordingPaths, @escaping (CaptureEvent) -> Void) -> any CaptureDriving
    private let makeDriver: DriverFactory
    private let makeMeetingDriver: DriverFactory?
    private let deadline: UInt64
    private var driver: (any CaptureDriving)?
    private var generation: UUID?
    private var startWaiter: CheckedContinuation<Void, Error>?
    private var stopWaiters: [CheckedContinuation<CaptureCompletion, Error>] = []
    private var stopRequested = false
    private var completion: CaptureCompletion?
    private(set) var isActive = false
    var onInterruption: (() -> Void)?
    var onMicrophoneChanged: ((String) -> Void)?
    var onMicrophoneSwitchFailed: (() -> Void)?
    var onSourceLost: ((MeetingMixer.Source) -> Void)?

    init(deadlineNanoseconds: UInt64 = 15_000_000_000, makeMeetingDriver: DriverFactory? = nil, makeDriver: @escaping DriverFactory) {
        deadline = deadlineNanoseconds
        self.makeDriver = makeDriver
        self.makeMeetingDriver = makeMeetingDriver
    }

    func start(microphoneID: String, paths: RecordingPaths) async throws {
        try await startDriver { event in makeDriver(microphoneID, paths, event) }
    }

    func startMeeting(microphoneID: String, paths: RecordingPaths) async throws {
        guard let makeMeetingDriver else { throw CaptureFailure.configuration }
        try await startDriver { event in makeMeetingDriver(microphoneID, paths, event) }
    }

    func switchMicrophone(to id: String) {
        guard isActive, !stopRequested else { return }
        driver?.switchMicrophone(to: id)
    }

    private func startDriver(_ factory: (@escaping (CaptureEvent) -> Void) -> any CaptureDriving) async throws {
        guard !isActive else { throw CaptureFailure.busy }
        let id = UUID()
        generation = id
        completion = nil
        stopRequested = false
        isActive = true
        driver = factory { [weak self] event in
            Task { @MainActor in self?.receive(event, id: id) }
        }
        try await withCheckedThrowingContinuation { continuation in
            startWaiter = continuation
            driver?.start()
            Task { [weak self] in
                guard let self else { return }
                try? await Task.sleep(nanoseconds: self.deadline)
                guard self.generation == id, let waiter = self.startWaiter else { return }
                self.startWaiter = nil
                waiter.resume(throwing: CaptureFailure.timeout)
                self.driver?.stop()
            }
        }
    }

    func stop() async throws -> CaptureCompletion {
        if !isActive, let completion { return completion }
        guard let id = generation, isActive else { throw CaptureFailure.start }
        return try await withCheckedThrowingContinuation { continuation in
            stopWaiters.append(continuation)
            if !stopRequested {
                stopRequested = true
                driver?.stop()
                Task { [weak self] in
                    guard let self else { return }
                    try? await Task.sleep(nanoseconds: self.deadline)
                    guard self.generation == id, self.isActive else { return }
                    let waiters = self.stopWaiters
                    self.stopWaiters = []
                    for waiter in waiters { waiter.resume(throwing: CaptureFailure.timeout) }
                }
            }
        }
    }

    private func receive(_ event: CaptureEvent, id: UUID) {
        guard generation == id, isActive else { return }
        switch event {
        case .started:
            if let waiter = startWaiter {
                startWaiter = nil
                waiter.resume()
            } else if !stopRequested {
                stopRequested = true
                driver?.stop()
            }
        case .finished(let result):
            finish(result)
        case .microphoneChanged(let microphoneID):
            if !stopRequested { onMicrophoneChanged?(microphoneID) }
        case .microphoneSwitchFailed:
            if !stopRequested { onMicrophoneSwitchFailed?() }
        case .sourceLost(let source):
            if !stopRequested { onSourceLost?(source) }
        case .failedToStart:
            finish(CaptureCompletion(interrupted: true))
        }
    }

    private func finish(_ result: CaptureCompletion) {
        let unexpected = !stopRequested && startWaiter == nil
        isActive = false
        completion = result
        driver = nil
        if let waiter = startWaiter { startWaiter = nil; waiter.resume(throwing: CaptureFailure.start) }
        let waiters = stopWaiters
        stopWaiters = []
        for waiter in waiters { waiter.resume(returning: result) }
        if unexpected { onInterruption?() }
    }
}
