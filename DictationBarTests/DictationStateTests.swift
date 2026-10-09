import XCTest
@testable import DictationBar

final class DictationStateTests: XCTestCase {
    @MainActor
    func testSessionRetainsMicrophoneAndFolderSnapshot() async throws {
        let config = AppConfiguration(microphoneID: "A", folderBookmark: Data([1]))
        let model = DictationModel(profile: .testing, configuration: config)
        let token = try XCTUnwrap(model.begin(origin: .liveDictation))
        model.configuration = AppConfiguration(microphoneID: "B", folderBookmark: Data([2]))
        XCTAssertEqual(model.session?.configuration, config)
        model.transition(to: .recording, token: token)
        XCTAssertEqual(model.phase, .recording)
    }

    @MainActor
    func testBusyGateAndStaleCallbacksDoNotStartOrOverwriteNextOperation() async throws {
        let model = DictationModel(profile: .testing)
        let old = try XCTUnwrap(model.begin(origin: .liveDictation))
        XCTAssertNil(model.begin(origin: .liveDictation))
        model.finish(token: old)
        let new = try XCTUnwrap(model.begin(origin: .historyRetry, id: old.id))
        model.transition(to: .inserting, token: old)
        model.finish(token: old, error: "stale")
        XCTAssertEqual(model.activeToken, new)
        XCTAssertEqual(model.phase, .transcribing)
        XCTAssertNil(model.message)
    }

    @MainActor
    func testInsertionIsClaimedOnceOnlyForLiveOperationWithoutQuit() async throws {
        let model = DictationModel(profile: .testing)
        let live = try XCTUnwrap(model.begin(origin: .liveDictation))
        XCTAssertTrue(model.claimInsertion(token: live))
        XCTAssertFalse(model.claimInsertion(token: live))
        model.finish(token: live)
        let retry = try XCTUnwrap(model.begin(origin: .historyRetry))
        XCTAssertFalse(model.claimInsertion(token: retry))
        model.finish(token: retry)
        let quitting = try XCTUnwrap(model.begin(origin: .liveDictation))
        model.requestQuit()
        XCTAssertFalse(model.claimInsertion(token: quitting))
        model.finish(token: quitting)
        XCTAssertNil(model.begin(origin: .liveDictation))
    }
}
