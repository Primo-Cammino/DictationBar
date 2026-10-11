import XCTest
@testable import DictationBar

@MainActor
final class MeetingPipelineTests: XCTestCase {
    func testMeetingRecordsWithoutEscapeAndSavesWithoutTranscription() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        try await f.startMeeting()
        XCTAssertEqual(f.recorder.meetingStarts, 1)
        XCTAssertEqual(f.systemAudio.requests, 1)
        XCTAssertFalse(f.shortcuts.escapeActive, "Escape stays free for Zoom or Teams")
        let entry = try XCTUnwrap(f.model.history.first)
        XCTAssertTrue(entry.isMeeting)
        XCTAssertTrue(entry.filename.hasPrefix("Meeting-"))
        f.model.toggleMeeting()
        try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.transcriber.calls, 0)
        XCTAssertEqual(f.inserter.calls, 0)
        XCTAssertEqual(f.model.history.first?.status, .pending)
        XCTAssertNotNil(f.model.history.first?.duration)
        XCTAssertEqual(f.model.message, "Meeting gespeichert.")
    }

    func testDictationShortcutDuringMeetingKeepsMeetingRunning() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        try await f.startMeeting()
        f.model.toggleRecording()
        XCTAssertEqual(f.model.phase, .recording)
        XCTAssertEqual(f.model.activeToken?.origin, .meeting)
        XCTAssertEqual(f.model.message, "Meeting läuft. Diktat ist währenddessen gesperrt.")
        await Task.yield()
        XCTAssertEqual(f.recorder.starts, 1)
        XCTAssertEqual(f.recorder.stops, 0)
        XCTAssertEqual(f.model.history.count, 1)
    }

    func testMeetingToggleDuringTranscriptionIsRefusedWithReason() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.transcriber.hold = true
        try await f.start(); f.stop()
        try await f.wait { f.transcriber.response != nil }
        f.model.toggleMeeting()
        XCTAssertEqual(f.recorder.meetingStarts, 0)
        XCTAssertEqual(f.model.message, "Kein Meeting: Eine Transkription läuft.")
        XCTAssertEqual(f.model.phase, .transcribing)
        f.transcriber.release()
        try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.model.history.count, 1)
    }

    func testDeniedSystemAudioCreatesNoJournalAndNamesTheSetting() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.systemAudio.granted = false
        f.model.toggleMeeting()
        try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.recorder.starts, 0)
        XCTAssertTrue(f.model.message?.contains("Bildschirm- & Systemaudioaufnahme") == true)
        let snapshot = try await f.history.load()
        XCTAssertTrue(snapshot.entries.isEmpty)
    }

    func testQuitDuringMeetingKeepsWAVAsNeutralMeetingEntry() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        try await f.startMeeting()
        let mayQuit = await f.model.terminateSafely()
        XCTAssertTrue(mayQuit)
        XCTAssertEqual(f.transcriber.calls, 0)
        let snapshot = try await f.history.load()
        let entry = try XCTUnwrap(snapshot.entries.first)
        XCTAssertTrue(entry.isMeeting)
        XCTAssertNotNil(entry.duration)
        XCTAssertNil(entry.visibleMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: f.files.folder.appendingPathComponent(entry.filename).path))
    }

    func testUserStopWinsOverSimultaneousInterruption() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.recorder.holdStart = true
        f.model.toggleMeeting()
        try await f.wait { f.recorder.startWaiter != nil }
        f.model.stopRecording(reason: .interrupted)
        f.model.stopRecording(reason: .normal)
        f.recorder.releaseStart()
        try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.model.history.first?.status, .pending)
        XCTAssertEqual(f.model.message, "Meeting gespeichert.")
    }

    func testMeetingToggleWhilePreparingChangesNothing() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.recorder.holdStart = true
        f.model.toggleMeeting()
        try await f.wait { f.recorder.startWaiter != nil }
        f.model.toggleMeeting()
        f.recorder.releaseStart()
        try await f.wait { f.model.phase == .recording }
        XCTAssertEqual(f.recorder.stops, 0)
        XCTAssertEqual(f.recorder.meetingStarts, 1)
    }

    func testLostSourceKeepsMeetingRunningAndWarnsUntilItEnds() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        try await f.startMeeting()
        f.recorder.onSourceLost?(.microphone)
        XCTAssertEqual(f.model.missingSource, .microphone)
        XCTAssertEqual(f.model.phase, .recording)
        XCTAssertEqual(f.recorder.stops, 0)
        f.model.toggleMeeting()
        try await f.wait { !f.model.isBusy }
        XCTAssertNil(f.model.missingSource)
    }
}
