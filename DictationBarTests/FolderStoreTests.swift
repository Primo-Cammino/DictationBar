import XCTest
@testable import DictationBar

final class FolderStoreTests: XCTestCase {
    func testFolderAndMicrophoneSurviveNewStoreAndDoNotRebindOldEntry() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let oldEntry = try f.entry()
        let configuration = AppConfiguration(microphoneID: "chosen", folderBookmark: oldEntry.folderBookmark)
        try await FolderStore(supportURL: f.support).save(configuration)
        let loaded = try await FolderStore(supportURL: f.support).load()
        XCTAssertEqual(loaded, configuration)
        let other = f.root.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try await FolderStore(supportURL: f.support).save(AppConfiguration(folderBookmark: FolderStore.bookmark(for: other)))
        XCTAssertEqual(try FolderStore.resolve(oldEntry.folderBookmark).url.standardizedFileURL, f.folder.standardizedFileURL)
    }

    func testMissingFolderNeverFallsBackOrCreatesDirectory() throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let bookmark = try FolderStore.bookmark(for: f.folder)
        try FileManager.default.removeItem(at: f.folder)
        XCTAssertThrowsError(try FolderStore.resolve(bookmark))
        XCTAssertThrowsError(try FolderStore.resolve(nil))
        XCTAssertFalse(FileManager.default.fileExists(atPath: f.folder.path))
    }

    func testMalformedConfigurationIsRetainedAndNotSilentlyReset() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        try FileManager.default.createDirectory(at: f.support, withIntermediateDirectories: true)
        let url = f.support.appendingPathComponent("configuration.json")
        let original = Data("{broken".utf8)
        try original.write(to: url)
        do { _ = try await FolderStore(supportURL: f.support).load(); XCTFail("Expected error") }
        catch { XCTAssertEqual(try Data(contentsOf: url), original) }
    }

    func testConfigurationWithRemovedBrowserSettingStillLoads() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        try FileManager.default.createDirectory(at: f.support, withIntermediateDirectories: true)
        try Data(#"{"microphoneID":"chosen","preferBluetooth":false,"browserSuggestions":true}"#.utf8)
            .write(to: f.support.appendingPathComponent("configuration.json"))
        let loaded = try await FolderStore(supportURL: f.support).load()
        XCTAssertEqual(loaded.microphoneID, "chosen")
        XCTAssertEqual(loaded.preferBluetooth, false)
    }
}
