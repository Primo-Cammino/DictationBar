import Carbon
import XCTest
@testable import DictationBar

final class ModelRecoveryTests: XCTestCase {
    private var optionR: DictationShortcut {
        DictationShortcut(keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(optionKey))!
    }

    @MainActor
    func testFreeShortcutRetriesFailedStartupRegistrationWithoutRestart() async throws {
        let fixture = try await PipelineFixture(profile: .production, shortcutRegistrationFails: true)
        defer { fixture.files.cleanup() }
        XCTAssertNotNil(fixture.model.shortcutMessage)
        XCTAssertEqual(fixture.shortcuts.registrations, 1)
        fixture.shortcuts.registrationFails = false
        await fixture.model.configureShortcut(optionR)
        XCTAssertEqual(fixture.shortcuts.registrations, 2)
        XCTAssertEqual(fixture.shortcuts.configuredShortcut, optionR)
        XCTAssertNil(fixture.model.shortcutMessage)
        XCTAssertEqual(fixture.model.shortcut, optionR)
        let saved = try await FolderStore(supportURL: fixture.files.support).load()
        XCTAssertEqual(saved.shortcut, optionR)
    }

    @MainActor
    func testRepeatedRegistrationFailureRetainsErrorAndPreviousSelection() async throws {
        let fixture = try await PipelineFixture(profile: .production, shortcutRegistrationFails: true)
        defer { fixture.files.cleanup() }
        await fixture.model.configureShortcut(optionR)
        XCTAssertEqual(fixture.shortcuts.registrations, 2)
        XCTAssertNotNil(fixture.model.shortcutMessage)
        XCTAssertEqual(fixture.model.shortcut, .default)
        let saved = try await FolderStore(supportURL: fixture.files.support).load()
        XCTAssertNil(saved.shortcut)
    }

    @MainActor
    func testTestingShortcutConfigurationRemainsPassive() async throws {
        let fixture = try await PipelineFixture()
        defer { fixture.files.cleanup() }
        await fixture.model.configureShortcut(optionR)
        XCTAssertEqual(fixture.shortcuts.registrations, 0)
        XCTAssertEqual(fixture.model.shortcut, optionR)
    }

    @MainActor
    func testDeadlineThenLateShutdownWithEmptyWAVAllowsRepairNextRecordingAndQuit() async throws {
        let fixture = try await PipelineFixture()
        defer { fixture.files.cleanup() }
        let empty = LocalStoreFixture.wav(frames: 0)
        let staging = try await timedOutCapture(fixture, audio: empty)
        fixture.model.repairPreservation()
        XCTAssertTrue(fixture.model.needsPreservation)
        XCTAssertFalse(fixture.model.canStart)
        fixture.recorder.confirmLateShutdown()
        try await repairAndWait(fixture)
        XCTAssertFalse(fixture.model.needsPreservation)
        XCTAssertTrue(fixture.model.canStart)
        XCTAssertEqual(fixture.model.history.first?.status, .failed)
        XCTAssertNil(fixture.model.history.first?.duration)
        XCTAssertEqual(try Data(contentsOf: staging), empty)
        guard fixture.model.canStart else { return }
        fixture.recorder.startFailure = nil
        fixture.recorder.audio = LocalStoreFixture.wav()
        try await fixture.start(); fixture.stop()
        try await fixture.wait { !fixture.model.isBusy }
        XCTAssertEqual(fixture.recorder.starts, 2)
        XCTAssertEqual(fixture.transcriber.calls, 1)
        XCTAssertEqual(fixture.model.history.count, 2)
        let mayQuit = await fixture.model.terminateSafely()
        XCTAssertTrue(mayQuit)
    }

    @MainActor
    func testInvalidAudioMetadataFailureKeepsGateUntilRepairSucceeds() async throws {
        let writes = RecoveryWriteGate()
        let fixture = try await PipelineFixture(beforeWrite: { try writes.beforeWrite() })
        defer { fixture.files.cleanup() }
        let empty = LocalStoreFixture.wav(frames: 0)
        let staging = try await timedOutCapture(fixture, audio: empty)
        fixture.recorder.confirmLateShutdown()
        writes.fail = true
        try await repairAndWait(fixture)
        XCTAssertTrue(fixture.model.needsPreservation)
        XCTAssertFalse(fixture.model.canStart)
        let mayQuitBeforeRepair = await fixture.model.terminateSafely()
        XCTAssertFalse(mayQuitBeforeRepair)
        XCTAssertEqual(try Data(contentsOf: staging), empty)
        writes.fail = false
        try await repairAndWait(fixture)
        XCTAssertFalse(fixture.model.needsPreservation)
        XCTAssertTrue(fixture.model.canStart)
        XCTAssertEqual(fixture.model.history.first?.status, .failed)
        let mayQuitAfterRepair = await fixture.model.terminateSafely()
        XCTAssertTrue(mayQuitAfterRepair)
        XCTAssertEqual(fixture.transcriber.calls, 0)
    }

    @MainActor
    func testLateMalformedRIFFPreservesBytesAndCommitsFailedHistory() async throws {
        let fixture = try await PipelineFixture()
        defer { fixture.files.cleanup() }
        let malformed = Data("RIFF\u{00}\u{00}\u{00}\u{00}WAVE".utf8)
        let staging = try await timedOutCapture(fixture, audio: malformed)
        fixture.recorder.confirmLateShutdown()
        try await repairAndWait(fixture)
        XCTAssertFalse(fixture.model.needsPreservation)
        XCTAssertEqual(fixture.model.history.first?.status, .failed)
        XCTAssertEqual(try Data(contentsOf: staging), malformed)
        XCTAssertEqual(fixture.transcriber.calls, 0)
    }

    func testMalformedRIFFIsStructuralInvalidWAVWhileMissingFileRemainsIOError() throws {
        let files = try LocalStoreFixture()
        defer { files.cleanup() }
        let malformed = files.folder.appendingPathComponent("malformed.wav")
        try Data("RIFF\u{00}\u{00}\u{00}\u{00}WAVE".utf8).write(to: malformed)
        XCTAssertThrowsError(try WAVValidator.inspect(malformed)) { error in
            let underlying = error as NSError
            XCTAssertEqual(error as? LocalStoreError, .invalidWAV,
                           "Observed \(underlying.domain) code \(underlying.code)")
        }
        XCTAssertThrowsError(try WAVValidator.inspect(files.folder.appendingPathComponent("missing.wav"))) { error in
            XCTAssertNil(error as? LocalStoreError)
        }
    }

    @MainActor
    func testFailedBluetoothSwitchKeepsActualSourceAndSingleRecording() async throws {
        let fixture = try await PipelineFixture()
        defer { fixture.files.cleanup() }
        try await fixture.start()
        let sessionID = fixture.model.session?.id
        fixture.recorder.switchFails = true
        fixture.microphone.devices.append(Microphone(id: "bt", name: "Bluetooth", isBluetooth: true))
        fixture.microphone.onDevicesChanged?()
        XCTAssertEqual(fixture.recorder.switches, ["bt"])
        XCTAssertEqual(fixture.model.actualMicrophoneID, "selected")
        XCTAssertEqual(fixture.recorder.device, "selected")
        XCTAssertEqual(fixture.model.session?.id, sessionID)
        XCTAssertNotNil(fixture.model.message)
        fixture.stop()
        try await fixture.wait { !fixture.model.isBusy }
        XCTAssertEqual(fixture.recorder.starts, 1)
        XCTAssertEqual(fixture.model.history.count, 1)
        XCTAssertNotNil(fixture.model.history.first?.duration)
    }

    @MainActor
    func testConfirmedFailedStartCollisionRetainsAudioGateAndBothFiles() async throws {
        let fixture = try await PipelineFixture()
        defer { fixture.files.cleanup() }
        fixture.recorder.startFailure = .start
        fixture.recorder.confirmsShutdownOnStartFailure = true
        var final: URL?
        fixture.recorder.beforeStartFailure = {
            let entry = try XCTUnwrap(fixture.model.history.first)
            let path = fixture.files.folder.appendingPathComponent(entry.filename)
            try LocalStoreFixture.wav().write(to: path)
            final = path
        }
        fixture.model.toggleRecording()
        try await fixture.wait { fixture.recorder.starts == 1 && !fixture.model.isBusy }
        XCTAssertFalse(fixture.recorder.isActive)
        XCTAssertTrue(fixture.model.needsPreservation)
        XCTAssertFalse(fixture.model.canStart)
        let entry = try XCTUnwrap(fixture.model.history.first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.files.folder.appendingPathComponent(entry.stagingFilename).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(final).path))
        let mayQuit = await fixture.model.terminateSafely()
        XCTAssertFalse(mayQuit)
        XCTAssertEqual(fixture.transcriber.calls, 0)
    }

    @MainActor
    func testConfirmedFailedStartMetadataFailureRetainsGateUntilSuccessfulRepair() async throws {
        let writes = RecoveryWriteGate()
        let fixture = try await PipelineFixture(beforeWrite: { try writes.beforeWrite() })
        defer { fixture.files.cleanup() }
        fixture.recorder.audio = LocalStoreFixture.wav(frames: 0)
        fixture.recorder.startFailure = .start
        fixture.recorder.confirmsShutdownOnStartFailure = true
        fixture.recorder.beforeStartFailure = { writes.fail = true }
        fixture.model.toggleRecording()
        try await fixture.wait { fixture.recorder.starts == 1 && !fixture.model.isBusy }
        XCTAssertFalse(fixture.recorder.isActive)
        XCTAssertTrue(fixture.model.needsPreservation)
        XCTAssertFalse(fixture.model.canStart)
        writes.fail = false
        try await repairAndWait(fixture)
        XCTAssertFalse(fixture.model.needsPreservation)
        XCTAssertTrue(fixture.model.canStart)
        XCTAssertEqual(fixture.model.history.first?.status, .failed)
        XCTAssertEqual(fixture.transcriber.calls, 0)
    }

    @MainActor
    func testLateShutdownReadErrorRetainsAudioGateUntilOriginalFileIsReachable() async throws {
        let fixture = try await PipelineFixture()
        defer { fixture.files.cleanup() }
        let staging = try await timedOutCapture(fixture, audio: LocalStoreFixture.wav())
        let moved = fixture.files.folder.appendingPathComponent("retained-original.wav")
        try FileManager.default.moveItem(at: staging, to: moved)
        fixture.recorder.confirmLateShutdown()
        try await repairAndWait(fixture)
        XCTAssertTrue(fixture.model.needsPreservation)
        XCTAssertFalse(fixture.model.canStart)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        try FileManager.default.moveItem(at: moved, to: staging)
        try await repairAndWait(fixture)
        XCTAssertFalse(fixture.model.needsPreservation)
        XCTAssertTrue(fixture.model.canStart)
        XCTAssertEqual(fixture.model.history.first?.status, .interrupted)
        XCTAssertEqual(fixture.transcriber.calls, 0)
    }

    @MainActor
    private func repairAndWait(_ fixture: PipelineFixture) async throws {
        let repair = try XCTUnwrap(fixture.model.repairPreservation())
        await repair.value
    }

    @MainActor
    private func timedOutCapture(_ fixture: PipelineFixture, audio: Data) async throws -> URL {
        fixture.recorder.audio = audio
        fixture.recorder.startFailure = .timeout
        fixture.model.toggleRecording()
        try await fixture.wait { fixture.recorder.starts == 1 && !fixture.model.isBusy }
        XCTAssertTrue(fixture.recorder.isActive)
        XCTAssertTrue(fixture.model.needsPreservation)
        XCTAssertFalse(fixture.model.canStart)
        let entry = try XCTUnwrap(fixture.model.history.first)
        return fixture.files.folder.appendingPathComponent(entry.stagingFilename)
    }
}

private final class RecoveryWriteGate {
    private let lock = NSLock()
    private var failing = false
    var fail: Bool {
        get { lock.lock(); defer { lock.unlock() }; return failing }
        set { lock.lock(); failing = newValue; lock.unlock() }
    }
    func beforeWrite() throws {
        if fail { throw CocoaError(.fileWriteNoPermission) }
    }
}
