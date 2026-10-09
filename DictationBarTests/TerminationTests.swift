import XCTest
@testable import DictationBar

final class TerminationTests: XCTestCase {
    @MainActor
    func testQuitDuringRecordingPreservesWAVWithoutTranscriptionAndStartupDoesNotResume() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        try await f.start()
        let mayQuit = await f.model.terminateSafely()
        XCTAssertTrue(mayQuit)
        XCTAssertEqual(f.transcriber.calls, 0)
        XCTAssertEqual(f.inserter.calls, 0)
        let restarted = RecordingStore(history: HistoryStore(supportURL: f.files.support))
        let snapshot = try await restarted.recover()
        XCTAssertEqual(snapshot.entries.first?.status, .interrupted)
        XCTAssertNotNil(snapshot.entries.first?.duration)
        XCTAssertEqual(f.transcriber.calls, 0)
    }

    @MainActor
    func testQuitBeforePermissionCompletesInvalidatesLateStart() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.microphone.holdPermission = true
        f.model.toggleRecording()
        try await f.wait { f.microphone.permission != nil }
        let mayQuit = await f.model.terminateSafely()
        XCTAssertTrue(mayQuit)
        f.microphone.grant()
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(f.recorder.starts, 0)
        let snapshot = try await f.history.load()
        XCTAssertTrue(snapshot.entries.isEmpty)
    }

    @MainActor
    func testQuitDuringCaptureStartWaitsForLocalFinalizationButStartsNoHTTP() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.recorder.holdStart = true
        f.model.toggleRecording()
        try await f.wait { f.recorder.startWaiter != nil }
        let quitting = Task { await f.model.terminateSafely() }
        try await f.wait { f.model.quitRequested }
        f.recorder.releaseStart()
        let mayQuit = await quitting.value
        XCTAssertTrue(mayQuit)
        XCTAssertEqual(f.recorder.stops, 1)
        XCTAssertEqual(f.transcriber.calls, 0)
        XCTAssertNotNil(f.model.history.first?.duration)
    }

    @MainActor
    func testQuitWinsDuringNormalStopFinalization() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.recorder.holdStop = true
        try await f.start(); f.stop()
        try await f.wait { f.recorder.stopWaiter != nil }
        let quitting = Task { await f.model.terminateSafely() }
        try await f.wait { f.model.quitRequested }
        f.recorder.releaseStop()
        let mayQuit = await quitting.value
        XCTAssertTrue(mayQuit)
        XCTAssertEqual(f.transcriber.calls, 0)
    }

    @MainActor
    func testQuitDuringHTTPDoesNotWaitForReplyAndIgnoresLateText() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.transcriber.hold = true
        try await f.start(); f.stop()
        try await f.wait { f.transcriber.response != nil }
        let mayQuit = await f.model.terminateSafely()
        XCTAssertTrue(mayQuit)
        f.transcriber.release()
        try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(f.inserter.calls, 0)
        let recovered = try await RecordingStore(history: HistoryStore(supportURL: f.files.support)).recover()
        XCTAssertEqual(recovered.entries.first?.status, .pending)
        XCTAssertNil(recovered.entries.first?.transcript)
    }

    @MainActor
    func testQuitDuringInsertionPreventsDelayedPasteAndKeepsText() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.inserter.hold = true
        try await f.start(); f.stop()
        try await f.wait { f.inserter.waiter != nil }
        let quitting = Task { await f.model.terminateSafely() }
        try await f.wait { f.model.quitRequested }
        f.inserter.release()
        let mayQuit = await quitting.value
        XCTAssertTrue(mayQuit)
        XCTAssertEqual(f.inserter.calls, 0)
        XCTAssertNotNil(f.model.history.first?.transcript)
    }

    @MainActor
    func testLocalWriteFailureRefusesQuitAndKeepsAppOpen() async throws {
        var writes = 0
        let f = try await PipelineFixture(beforeWrite: {
            writes += 1
            if writes >= 3 { throw CocoaError(.fileWriteNoPermission) }
        }); defer { f.files.cleanup() }
        try await f.start()
        let mayQuit = await f.model.terminateSafely()
        XCTAssertFalse(mayQuit)
        XCTAssertFalse(f.model.quitRequested)
        XCTAssertTrue(f.model.needsPreservation)
        let files = try FileManager.default.contentsOfDirectory(at: f.files.folder, includingPropertiesForKeys: nil)
        XCTAssertTrue(files.contains { $0.pathExtension == "wav" })
        XCTAssertEqual(f.transcriber.calls, 0)
    }
    @MainActor
    func testQuitWaitsForTranscriptCommitAndPreventsPaste() async throws {
        let gate = TranscriptCommitGate()
        let f = try await PipelineFixture(beforeWrite: { try gate.beforeWrite() })
        defer { gate.release(); f.files.cleanup() }
        f.transcriber.hold = true
        try await f.start(); f.stop()
        try await f.wait { f.transcriber.response != nil }
        gate.arm(failing: false)
        f.transcriber.release()
        try await f.wait { gate.entered }
        let quitting = Task { await f.model.terminateSafely() }
        try await f.wait { f.model.quitRequested }
        XCTAssertTrue(f.model.isBusy)
        gate.release()
        let mayQuit = await quitting.value
        XCTAssertTrue(mayQuit)
        XCTAssertEqual(f.inserter.calls, 0)
        XCTAssertNotNil(f.model.history.first?.transcript)
    }

    @MainActor
    func testTranscriptCommitFailureRefusesQuitUntilLocalRepairSucceeds() async throws {
        let gate = TranscriptCommitGate()
        let f = try await PipelineFixture(beforeWrite: { try gate.beforeWrite() })
        defer { gate.release(); f.files.cleanup() }
        f.transcriber.hold = true
        try await f.start(); f.stop()
        try await f.wait { f.transcriber.response != nil }
        gate.arm(failing: true)
        f.transcriber.release()
        try await f.wait { gate.entered }
        let quitting = Task { await f.model.terminateSafely() }
        try await f.wait { f.model.quitRequested }
        gate.release()
        let mayQuit = await quitting.value
        XCTAssertFalse(mayQuit)
        XCTAssertTrue(f.model.needsPreservation)
        XCTAssertEqual(f.inserter.calls, 0)
        gate.allowWrites()
        f.model.repairPreservation()
        try await f.wait { !f.model.needsPreservation && !f.model.isBusy }
        XCTAssertNotNil(f.model.history.first?.transcript)
        let repairedQuit = await f.model.terminateSafely()
        XCTAssertTrue(repairedQuit)
        XCTAssertEqual(f.transcriber.calls, 1)
    }

    @MainActor
    func testRepeatedQuitRequestsStopAndFinalizeCaptureOnlyOnce() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.recorder.holdStop = true
        try await f.start()
        let first = Task { await f.model.terminateSafely() }
        try await f.wait { f.recorder.stopWaiter != nil }
        let second = Task { await f.model.terminateSafely() }
        f.recorder.releaseStop()
        let firstResult = await first.value
        let secondResult = await second.value
        XCTAssertTrue(firstResult)
        XCTAssertTrue(secondResult)
        XCTAssertEqual(f.recorder.stops, 1)
        XCTAssertEqual(f.model.history.count, 1)
        XCTAssertEqual(f.transcriber.calls, 0)
    }

}

/// Holds only the history actor; the main actor must remain responsive to Quit.
private final class TranscriptCommitGate {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var armed = false
    private var held = false
    private var failing = false
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return held }
    func arm(failing: Bool) { lock.lock(); armed = true; self.failing = failing; lock.unlock() }
    func allowWrites() { lock.lock(); failing = false; lock.unlock() }
    func release() { semaphore.signal() }
    func beforeWrite() throws {
        lock.lock()
        let shouldHold = armed && !held
        if shouldHold { held = true }
        lock.unlock()
        if shouldHold { _ = semaphore.wait(timeout: .now() + 3) }
        lock.lock(); let fail = failing; lock.unlock()
        if fail { throw CocoaError(.fileWriteNoPermission) }
    }
}
