import XCTest
@testable import DictationBar

final class HistoryStoreTests: XCTestCase {
    func testDamagedAndUnknownSchemaRecordsDoNotHideValidHistoryOrChangeOriginals() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let store = HistoryStore(supportURL: f.support)
        let older = try f.entry(date: Date(timeIntervalSince1970: 100))
        let newer = try f.entry(date: Date(timeIntervalSince1970: 200))
        for entry in [older, newer] {
            let token = f.token(entry)
            await store.authorize(token)
            try await store.create(entry, token: token)
            await store.revoke(token)
        }
        let directory = await store.directory
        let broken = directory.appendingPathComponent("broken.json")
        let bytes = Data("{broken".utf8); try bytes.write(to: broken)
        var unknown = try f.entry(); unknown.schemaVersion = 99
        let unknownURL = directory.appendingPathComponent(unknown.id.uuidString + ".json")
        let unknownBytes = try JSONEncoder().encode(unknown); try unknownBytes.write(to: unknownURL)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.entries.map(\.id), [newer.id, older.id])
        XCTAssertEqual(loaded.warnings.count, 2)
        XCTAssertEqual(try Data(contentsOf: broken), bytes)
        XCTAssertEqual(try Data(contentsOf: unknownURL), unknownBytes)
    }

    func testExclusiveCreateAndGenerationGuardPreserveNewerResult() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let store = HistoryStore(supportURL: f.support)
        var entry = try f.entry(); let old = f.token(entry)
        await store.authorize(old); try await store.create(entry, token: old)
        do { try await store.create(entry, token: old); XCTFail("Expected collision") }
        catch { XCTAssertEqual(error as? LocalStoreError, .collision) }
        let current = f.token(entry, generation: 2)
        try await store.authorizeExisting(current)
        entry.transcript = "New result"
        try await store.save(entry, token: current)
        var stale = entry; stale.transcript = "Old result"
        do { try await store.save(stale, token: old); XCTFail("Expected stale rejection") }
        catch { XCTAssertEqual(error as? LocalStoreError, .staleOperation) }
        await store.revoke(old)
        entry.insertion = .historyOnly
        try await store.save(entry, token: current)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.entries.first?.transcript, "New result")
    }

    func testMeetingEntriesAreRecognizableAndOldJournalsStayDictations() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let store = HistoryStore(supportURL: f.support)
        let dictation = try f.entry()
        let meeting = HistoryEntry(id: UUID(), createdAt: Date(), microphoneID: "test-microphone",
                                   folderBookmark: try FolderStore.bookmark(for: f.folder), kind: .meeting)
        XCTAssertTrue(meeting.filename.hasPrefix("Meeting-"))
        XCTAssertTrue(meeting.stagingFilename.hasPrefix(".Meeting-"))
        for entry in [dictation, meeting] {
            let token = f.token(entry)
            await store.authorize(token); try await store.create(entry, token: token); await store.revoke(token)
        }
        let directory = await store.directory
        let journal = try Data(contentsOf: directory.appendingPathComponent(dictation.id.uuidString + ".json"))
        XCTAssertFalse(String(decoding: journal, as: UTF8.self).contains("kind"))
        let loaded = try await store.load()
        XCTAssertEqual(loaded.warnings, [])
        XCTAssertEqual(loaded.entries.first { $0.id == dictation.id }?.isMeeting, false)
        XCTAssertEqual(loaded.entries.first { $0.id == meeting.id }?.isMeeting, true)

        // A dictation journal relabelled as meeting keeps the Dictation- name and is rejected.
        var tampered = try JSONSerialization.jsonObject(with: journal) as! [String: Any]
        tampered["kind"] = "meeting"
        try JSONSerialization.data(withJSONObject: tampered)
            .write(to: directory.appendingPathComponent(dictation.id.uuidString + ".json"))
        let reloaded = try await store.load()
        XCTAssertEqual(reloaded.entries.map(\.id), [meeting.id])
        XCTAssertEqual(reloaded.warnings.count, 1)
    }

    func testMeetingEntryHidesTranscriptionHintUnlessFailed() throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        var meeting = HistoryEntry(id: UUID(), createdAt: Date(), microphoneID: "test-microphone",
                                   folderBookmark: try FolderStore.bookmark(for: f.folder), kind: .meeting)
        meeting.status = .interrupted
        meeting.message = "Aufnahme unterbrochen. Transkription bitte bewusst starten."
        XCTAssertNil(meeting.visibleMessage)
        meeting.status = .failed
        meeting.message = "Fehler"
        XCTAssertEqual(meeting.visibleMessage, "Fehler")
        var dictation = try f.entry()
        dictation.message = "Aufnahme unterbrochen. Transkription bitte bewusst starten."
        XCTAssertEqual(dictation.visibleMessage, dictation.message)
    }
}
