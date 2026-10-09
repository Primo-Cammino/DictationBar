import XCTest
@testable import DictationBar

final class GlobalShortcutTests: XCTestCase {
    @MainActor
    func testRepeatDoesNotToggleTwiceAndReleaseAllowsNextPress() async {
        let router = ShortcutEventRouter()
        var toggles = 0
        router.onToggle = { toggles += 1 }
        router.receive(id: 1, down: true)
        router.receive(id: 1, down: true)
        XCTAssertEqual(toggles, 1)
        router.receive(id: 1, down: false)
        router.receive(id: 1, down: true)
        XCTAssertEqual(toggles, 2)
    }

    @MainActor
    func testEscapeIsEffectiveOnlyDuringCaptureAndUsesOneStopCallback() async {
        let router = ShortcutEventRouter()
        var stops = 0
        router.onEscape = { stops += 1 }
        router.receive(id: 2, down: true)
        XCTAssertEqual(stops, 0)
        router.receive(id: 2, down: false)
        router.captureActive = true
        router.receive(id: 2, down: true)
        router.receive(id: 2, down: true)
        XCTAssertEqual(stops, 1)
        router.captureActive = false
        router.receive(id: 2, down: true)
        XCTAssertEqual(stops, 1)
        router.reset()
        router.captureActive = true
        router.receive(id: 2, down: true)
        XCTAssertEqual(stops, 2)
    }
}
