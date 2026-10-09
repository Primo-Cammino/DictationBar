import XCTest
@testable import DictationBar

final class LiveMicrophoneSwitchTests: XCTestCase {
    @MainActor
    func testLiveSwitchUsesSameDriverAndStopRejectsFurtherSwitches() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let driver = SwitchingDriver()
        let service = RecordingService { _, _, event in driver.event = event; return driver }
        let paths = RecordingPaths(staging: f.folder.appendingPathComponent("stage"), final: f.folder.appendingPathComponent("final"))
        let starting = Task { try await service.start(microphoneID: "built-in", paths: paths) }
        await Task.yield(); driver.event?(.started); try await starting.value
        var actual: String?
        service.onMicrophoneChanged = { actual = $0 }
        service.switchMicrophone(to: "bluetooth")
        await Task.yield()
        XCTAssertEqual(driver.switches, ["bluetooth"])
        XCTAssertEqual(actual, "bluetooth")
        XCTAssertTrue(service.isActive)
        XCTAssertEqual(driver.starts, 1)
        let stopping = Task { try await service.stop() }
        await Task.yield()
        service.switchMicrophone(to: "other")
        XCTAssertEqual(driver.switches, ["bluetooth"])
        driver.event?(.finished(CaptureCompletion(interrupted: false)))
        _ = try await stopping.value
    }
}

private final class SwitchingDriver: CaptureDriving {
    var event: ((CaptureEvent) -> Void)?
    var starts = 0
    var switches: [String] = []
    func start() { starts += 1 }
    func stop() { }
    func switchMicrophone(to id: String) {
        switches.append(id)
        event?(.microphoneChanged(id))
    }
}
