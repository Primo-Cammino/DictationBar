import XCTest
@testable import DictationBar

final class RuntimeInitializationTests: XCTestCase {
    func testExplicitTestProfileNeverConstructsNativeAdapters() {
        let profile = RuntimeProfile.resolve(environment: ["DICTATIONBAR_RUNTIME": "testing"])
        var nativeConstructions = 0
        let result = RuntimeFactory.make(profile: profile, production: {
            nativeConstructions += 1
            return "native"
        }, testing: { "test" })
        XCTAssertEqual(result, "test")
        XCTAssertEqual(nativeConstructions, 0)
    }

    func testHostedAppUsesExplicitTestingProfile() {
        XCTAssertEqual(RuntimeProfile.resolve(environment: ProcessInfo.processInfo.environment), .testing)
    }

    @MainActor
    func testRuntimeConstructionDoesNotStartWorkOrRequestQuit() async {
        let model = DictationModel(profile: .testing)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertNil(model.activeToken)
        XCTAssertNil(model.session)
        XCTAssertFalse(model.quitRequested)
    }
}
