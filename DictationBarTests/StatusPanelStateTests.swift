import AppKit
import XCTest
@testable import DictationBar

@MainActor
final class StatusPanelStateTests: XCTestCase {
    func testDictationShowsRecordingThenTranscriptionThenNothing() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        XCTAssertNil(f.model.panelActivity)
        try await f.start()
        XCTAssertEqual(f.model.panelActivity, .dictation)
        f.transcriber.hold = true
        f.stop()
        try await f.wait { f.transcriber.response != nil }
        XCTAssertEqual(f.model.panelActivity, .transcription)
        f.transcriber.release()
        try await f.wait { !f.model.isBusy }
        XCTAssertNil(f.model.panelActivity)
        XCTAssertNil(f.model.notice)
    }

    func testHistoryTranscriptionShowsTranscriptionThenNothing() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.transcriber.failure = .network
        try await f.start(); f.stop(); try await f.wait { !f.model.isBusy }
        f.transcriber.failure = nil; f.transcriber.hold = true
        f.model.retry(try XCTUnwrap(f.model.history.first).id)
        try await f.wait { f.transcriber.response != nil }
        XCTAssertEqual(f.model.panelActivity, .transcription)
        f.transcriber.release()
        try await f.wait { !f.model.isBusy }
        XCTAssertNil(f.model.panelActivity)
    }

    func testMeetingPhasesAndDurationStartAtRecording() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.recorder.holdStart = true
        f.model.toggleMeeting()
        try await f.wait { f.recorder.startWaiter != nil }
        XCTAssertEqual(f.model.panelActivity, .meetingStarting)
        let begun = try XCTUnwrap(f.model.session?.createdAt)
        try await Task.sleep(nanoseconds: 20_000_000)
        f.recorder.releaseStart()
        try await f.wait { f.model.phase == .recording }
        guard case .meeting(let since)? = f.model.panelActivity else { return XCTFail("Expected running meeting") }
        XCTAssertGreaterThan(since.timeIntervalSince(begun), 0.015)
        f.recorder.holdStop = true
        f.model.toggleMeeting()
        try await f.wait { f.recorder.stopWaiter != nil }
        XCTAssertEqual(f.model.panelActivity, .meetingSaving)
        f.recorder.releaseStop()
        try await f.wait { !f.model.isBusy }
        let notice = try XCTUnwrap(f.model.notice)
        XCTAssertEqual(notice.kind, .saved)
        XCTAssertEqual(notice.text, "Meeting gespeichert.")
        XCTAssertEqual(notice.seconds, 6)
        XCTAssertTrue(try XCTUnwrap(notice.entry).isMeeting)
    }

    func testDictationShortcutDuringMeetingNotifiesAndKeepsSourceWarning() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        try await f.startMeeting()
        f.recorder.onSourceLost?(.microphone)
        f.model.toggleRecording()
        XCTAssertEqual(f.model.notice?.text, "Meeting läuft")
        XCTAssertEqual(f.model.notice?.kind, .info)
        XCTAssertEqual(f.model.missingSource, .microphone)
        guard case .meeting? = f.model.panelActivity else { return XCTFail("Meeting must keep running") }
    }

    func testMeetingEndedBySourceLossShowsInterruptedLonger() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        try await f.startMeeting()
        f.recorder.interrupted = true
        f.recorder.confirmLateShutdown()
        try await f.wait { !f.model.isBusy }
        let notice = try XCTUnwrap(f.model.notice)
        XCTAssertEqual(notice.kind, .interrupted)
        XCTAssertEqual(notice.text, "Meeting unterbrochen. Die Aufnahme bis dahin ist gespeichert.")
        XCTAssertEqual(notice.seconds, 15)
        XCTAssertNotNil(notice.entry)
    }

    func testDeniedSystemAudioNoticeOffersTheScreenRecordingSettings() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.systemAudio.granted = false
        f.model.toggleMeeting()
        try await f.wait { !f.model.isBusy }
        let notice = try XCTUnwrap(f.model.notice)
        XCTAssertEqual(notice.kind, .permission)
        XCTAssertTrue(notice.text.contains("Bildschirm- & Systemaudioaufnahme"))
        XCTAssertTrue(PanelNotice.systemAudioSettings.absoluteString.contains("Privacy_ScreenCapture"))
        XCTAssertNil(f.model.panelActivity)
    }

    func testFailureShowsErrorNoticeAndNoLastingActivity() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        f.microphone.granted = false
        f.model.toggleRecording()
        try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.model.notice?.kind, .error)
        XCTAssertEqual(f.model.notice?.seconds, 8)
        XCTAssertNil(f.model.panelActivity)
    }

    func testNewActivityReplacesNoticeAndOldTimerKeepsNewerNotice() async throws {
        let f = try await PipelineFixture(); defer { f.files.cleanup() }
        try await f.startMeeting()
        f.model.toggleMeeting()
        try await f.wait { !f.model.isBusy }
        XCTAssertEqual(f.model.notice?.kind, .saved)
        try await f.start()
        XCTAssertNil(f.model.notice, "A new dictation replaces the saved notice")
        f.model.toggleMeeting() // refused: dictation runs, 3 s notice
        try await Task.sleep(nanoseconds: 1_500_000_000)
        f.model.toggleMeeting() // second refusal, newer notice
        let newer = try XCTUnwrap(f.model.notice)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(f.model.notice?.id, newer.id, "The first timer must not hide the newer notice")
        try await f.wait { f.model.notice == nil }
    }

    func testPlacementUsesBottomRightOfMouseScreenUnlessUserPositionIsStillVisible() {
        let size = NSSize(width: 300, height: 60)
        let left = NSRect(x: 0, y: 0, width: 1_000, height: 800)
        let right = NSRect(x: 1_000, y: 0, width: 1_200, height: 900)
        XCTAssertEqual(StatusPanelPlacement.origin(size: size, saved: nil, visibleFrames: [left, right], mouseScreen: right),
                       NSPoint(x: 2_200 - 300 - 16, y: 16))
        let moved = NSPoint(x: 100, y: 500)
        XCTAssertEqual(StatusPanelPlacement.origin(size: size, saved: moved, visibleFrames: [left, right], mouseScreen: right),
                       moved)
        // The display the user dragged it to is gone.
        let offscreen = NSPoint(x: 3_000, y: 500)
        XCTAssertEqual(StatusPanelPlacement.origin(size: size, saved: offscreen, visibleFrames: [left], mouseScreen: left),
                       NSPoint(x: 1_000 - 300 - 16, y: 16))
    }
}
