import XCTest
@testable import DictationBar

final class RecordingStoreTests: XCTestCase {
    func testFinalizedAudioAndMetadataSurviveRestartAndRecoveryIsIdempotent() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let history = HistoryStore(supportURL: f.support)
        let recordings = RecordingStore(history: history)
        let entry = try f.entry(); let token = f.token(entry)
        let paths = try await recordings.prepare(entry, token: token)
        try LocalStoreFixture.wav().write(to: paths.staging)
        let saved = try await recordings.finalize(entry, token: token, interrupted: false)
        XCTAssertEqual(saved.status, .pending)
        XCTAssertEqual(saved.duration ?? 0, 0.01, accuracy: 0.0001)
        await history.revoke(token)
        let restarted = RecordingStore(history: HistoryStore(supportURL: f.support))
        let first = try await restarted.recover(); let second = try await restarted.recover()
        XCTAssertEqual(first.entries, second.entries)
        XCTAssertEqual(first.entries.first, saved)
        XCTAssertEqual(try Data(contentsOf: paths.final), LocalStoreFixture.wav())
    }

    func testStagingAndFinalCollisionsPreserveExistingFiles() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let store = RecordingStore(history: HistoryStore(supportURL: f.support))
        for finalCollision in [false, true] {
            let entry = try f.entry(); let paths = try await store.paths(for: entry)
            let existing = finalCollision ? paths.final : paths.staging
            let sentinel = Data("User data".utf8); try sentinel.write(to: existing)
            do { _ = try await store.prepare(entry, token: f.token(entry)); XCTFail("Expected collision") }
            catch { XCTAssertEqual(error as? LocalStoreError, .collision) }
            XCTAssertEqual(try Data(contentsOf: existing), sentinel)
        }
        let sameTime = Date()
        XCTAssertNotEqual(try f.entry(date: sameTime).filename, try f.entry(date: sameTime).filename)
    }

    func testRestartDoesNotMoveValidWAVThatCollidedDuringPreparation() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let history = HistoryStore(supportURL: f.support)
        let store = RecordingStore(history: history)
        let entry = try f.entry(); let paths = try await store.paths(for: entry)
        let sentinel = LocalStoreFixture.wav()
        try sentinel.write(to: paths.staging)
        do { _ = try await store.prepare(entry, token: f.token(entry)); XCTFail("Expected collision") }
        catch { XCTAssertEqual(error as? LocalStoreError, .collision) }
        let restarted = RecordingStore(history: HistoryStore(supportURL: f.support))
        let recovered = try await restarted.recover()
        XCTAssertEqual(recovered.entries.first?.status, .failed)
        XCTAssertEqual(try Data(contentsOf: paths.staging), sentinel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.final.path))
        let again = try await restarted.recover()
        XCTAssertEqual(again.entries, recovered.entries)
        XCTAssertEqual(try Data(contentsOf: paths.staging), sentinel)
    }

    func testCollisionAppearingImmediatelyBeforeRenameNeverOverwritesEitherFile() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let entry = try f.entry()
        let final = f.folder.appendingPathComponent(entry.filename)
        let sentinel = Data("Other file".utf8)
        let history = HistoryStore(supportURL: f.support)
        let store = RecordingStore(history: history, beforeRename: { try sentinel.write(to: final) })
        let paths = try await store.prepare(entry, token: f.token(entry))
        let audio = LocalStoreFixture.wav(); try audio.write(to: paths.staging)
        do { _ = try await store.finalize(entry, token: f.token(entry), interrupted: false); XCTFail("Expected collision") }
        catch { XCTAssertEqual(error as? LocalStoreError, .collision) }
        XCTAssertEqual(try Data(contentsOf: paths.staging), audio)
        XCTAssertEqual(try Data(contentsOf: paths.final), sentinel)
    }

    func testJournalFailurePreventsStagingAndCapturePreparation() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let history = HistoryStore(supportURL: f.support, beforeWrite: { throw CocoaError(.fileWriteNoPermission) })
        let store = RecordingStore(history: history)
        let entry = try f.entry(); let paths = try await store.paths(for: entry)
        do { _ = try await store.prepare(entry, token: f.token(entry)); XCTFail("Expected error") }
        catch { XCTAssertFalse(FileManager.default.fileExists(atPath: paths.staging.path)) }
    }

    func testMetadataFailureAfterRenameRetainsWAVAndRecoveryFinishesCheckpoint() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        var writes = 0
        let history = HistoryStore(supportURL: f.support, beforeWrite: {
            writes += 1
            if writes == 3 { throw CocoaError(.fileWriteNoPermission) }
        })
        let store = RecordingStore(history: history)
        let entry = try f.entry(); let token = f.token(entry)
        let paths = try await store.prepare(entry, token: token)
        try LocalStoreFixture.wav().write(to: paths.staging)
        do { _ = try await store.finalize(entry, token: token, interrupted: false); XCTFail("Expected error") }
        catch { XCTAssertTrue(FileManager.default.fileExists(atPath: paths.final.path)) }
        let restarted = RecordingStore(history: HistoryStore(supportURL: f.support))
        let recovered = try await restarted.recover()
        XCTAssertEqual(recovered.entries.first?.status, .pending)
        let again = try await restarted.recover()
        XCTAssertEqual(again.entries, recovered.entries)
    }

    func testInterruptedStagingIsSalvagedAndMissingWAVKeepsTranscript() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let history = HistoryStore(supportURL: f.support)
        let store = RecordingStore(history: history)
        var entry = try f.entry(); let token = f.token(entry)
        let paths = try await store.prepare(entry, token: token)
        try LocalStoreFixture.wav().write(to: paths.staging)
        await history.revoke(token)
        let recovered = try await store.recover()
        XCTAssertEqual(recovered.entries.first?.status, .interrupted)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.final.path))
        entry = try XCTUnwrap(recovered.entries.first)
        entry.transcript = "Retained text"
        try await history.authorizeExisting(token); try await history.save(entry, token: token); await history.revoke(token)
        try FileManager.default.removeItem(at: paths.final)
        let missing = try await store.recover()
        XCTAssertEqual(missing.entries.first?.transcript, "Retained text")
        XCTAssertEqual(missing.entries.first?.status, .complete)
        let again = try await store.recover()
        XCTAssertEqual(again.entries, missing.entries)
    }
}
