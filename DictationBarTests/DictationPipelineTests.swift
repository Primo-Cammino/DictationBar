import XCTest
@testable import DictationBar

final class DictationPipelineTests: XCTestCase {
    @MainActor
    func testLivePipelineSavesWAVAndTextBeforeOnePasteAndDoesNotQueueBusyStarts() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        XCTAssertEqual(f.recorder.starts, 0)
        XCTAssertEqual(f.transcriber.calls, 0)
        XCTAssertEqual(f.shortcuts.registrations, 0)
        try await f.start()
        XCTAssertEqual(f.recorder.device, "selected")
        f.transcriber.hold = true
        f.stop()
        try await f.wait { f.model.phase == .transcribing && f.transcriber.response != nil }
        XCTAssertEqual(f.model.history.first?.status, .transcribing)
        XCTAssertNotNil(f.model.history.first?.duration)
        for _ in 0..<5 { f.model.toggleRecording() }
        XCTAssertEqual(f.recorder.starts, 1)
        f.transcriber.release()
        try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.transcriber.calls, 1)
        XCTAssertEqual(f.inserter.calls, 1)
        XCTAssertTrue(f.inserter.persistedBeforePaste)
        XCTAssertEqual(f.model.history.first?.insertion, .confirmed)
        let entry = try XCTUnwrap(f.model.history.first)
        XCTAssertEqual(try WAVValidator.inspect(f.files.folder.appendingPathComponent(entry.filename)).frames, 480)
    }

    @MainActor
    func testFailedTranscriptionKeepsWAVAndManualRetryNeverPastes() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.transcriber.failure = .network
        try await f.start(); f.stop(); try await f.wait { !f.model.isBusy }
        let entry = try XCTUnwrap(f.model.history.first)
        XCTAssertEqual(entry.status, .failed)
        XCTAssertEqual(f.inserter.calls, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.files.folder.appendingPathComponent(entry.filename).path))
        f.transcriber.failure = nil; f.transcriber.hold = true
        f.model.retry(entry.id)
        try await f.wait { f.transcriber.response != nil }
        f.model.toggleRecording()
        XCTAssertEqual(f.recorder.starts, 1)
        f.transcriber.release()
        try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.model.history.first?.insertion, .historyOnly)
        XCTAssertNotNil(f.model.history.first?.transcript)
        XCTAssertEqual(f.inserter.calls, 0)
    }

    @MainActor
    func testDeniedMicrophoneCreatesNoCaptureOrJournal() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.microphone.granted = false
        f.model.toggleRecording()
        try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.recorder.starts, 0)
        XCTAssertEqual(f.transcriber.calls, 0)
        XCTAssertEqual(f.model.phase, .failed)
        let snapshot = try await f.history.load()
        XCTAssertTrue(snapshot.entries.isEmpty)
    }

    @MainActor
    func testEscapeUsesNormalStopAndProducesOneTranscript() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        try await f.start()
        XCTAssertTrue(f.shortcuts.escapeActive)
        f.shortcuts.onEscape?()
        f.shortcuts.onEscape?()
        try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.recorder.stops, 1)
        XCTAssertEqual(f.transcriber.calls, 1)
        XCTAssertFalse(f.shortcuts.escapeActive)
    }

    @MainActor
    func testLocalTextWriteFailureDoesNotPasteAndRetainsTextForRepair() async throws {
        var writes = 0
        var fail = true
        let f = try await PipelineFixture(beforeWrite: {
            writes += 1
            if writes >= 5 && fail { throw CocoaError(.fileWriteNoPermission) }
        }); defer { f.files.cleanup() }
        try await f.start(); f.stop(); try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.inserter.calls, 0)
        XCTAssertTrue(f.model.needsPreservation)
        XCTAssertFalse(f.model.canStart)
        fail = false
        f.model.repairPreservation()
        try await f.wait { !f.model.needsPreservation }
        XCTAssertEqual(f.model.history.first?.transcript, "Neutraler Testtext.")
        XCTAssertEqual(f.inserter.calls, 0)
    }
    @MainActor
    func testZeroFrameCaptureKeepsOriginalButAllowsNextRecordingAndQuit() async throws {
        for interrupted in [false, true] {
            let f = try await PipelineFixture(); defer { f.files.cleanup() }
            let invalid = LocalStoreFixture.wav(frames: 0)
            f.recorder.audio = invalid
            f.recorder.interrupted = interrupted
            try await f.start(); f.stop(); try await f.wait { !f.model.isBusy }
            let entry = try XCTUnwrap(f.model.history.first)
            XCTAssertEqual(entry.status, .failed)
            XCTAssertEqual(f.transcriber.calls, 0)
            XCTAssertEqual(f.inserter.calls, 0)
            XCTAssertEqual(try Data(contentsOf: f.files.folder.appendingPathComponent(entry.stagingFilename)), invalid)
            XCTAssertFalse(f.model.needsPreservation)
            XCTAssertTrue(f.model.canStart)
            f.recorder.audio = LocalStoreFixture.wav()
            f.recorder.interrupted = false
            try await f.start()
            XCTAssertEqual(f.recorder.starts, 2)
            let mayQuit = await f.model.terminateSafely()
            XCTAssertTrue(mayQuit)
            XCTAssertEqual(f.transcriber.calls, 0)
        }
    }

    @MainActor
    func testMeetingEntryIsNeverRetriedWhileOldBrowserEntryStaysTranscribable() async throws {
        var browserID = UUID(), meetingID = UUID()
        let f = try await PipelineFixture(existing: { files in
            var browser = try files.entry(date: Date(timeIntervalSince1970: 100))
            browser.sourceLabel = "Safari · Browser-Audio"
            let meeting = HistoryEntry(id: UUID(), createdAt: Date(timeIntervalSince1970: 200), microphoneID: "selected",
                                       folderBookmark: try FolderStore.bookmark(for: files.folder), kind: .meeting)
            browserID = browser.id; meetingID = meeting.id
            return [browser, meeting]
        }); defer { f.files.cleanup() }
        XCTAssertEqual(f.model.history.count, 2)
        f.model.retry(meetingID)
        XCTAssertFalse(f.model.isBusy)
        f.model.retry(browserID)
        try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.transcriber.calls, 1)
        XCTAssertNotNil(f.model.history.first { $0.id == browserID }?.transcript)
        XCTAssertNil(f.model.history.first { $0.id == meetingID }?.transcript)
    }
}
