import XCTest
@testable import DictationBar

final class BrowserBluetoothTests: XCTestCase {
    let browser = BrowserAudioTarget(bundleID: "test.browser", processID: 42, name: "Test Browser")

    func testPromptDismissalAndBusySuppressionLastUntilAudioStops() {
        var policy = BrowserSuggestionPolicy()
        XCTAssertEqual(policy.update([browser], enabled: true, busy: false), browser)
        policy.dismiss(browser)
        XCTAssertNil(policy.update([browser], enabled: true, busy: false))
        XCTAssertNil(policy.update([], enabled: true, busy: false))
        XCTAssertEqual(policy.update([browser], enabled: true, busy: false), browser)
        XCTAssertNil(policy.update([browser], enabled: true, busy: true))
        XCTAssertNil(policy.update([browser], enabled: true, busy: false))
    }

    func testBluetoothPriorityAndManualOverride() {
        let builtIn = Microphone(id: "internal", name: "Internal")
        let one = Microphone(id: "a", name: "Headset A", isBluetooth: true)
        let two = Microphone(id: "b", name: "Headset B", isBluetooth: true, isSystemDefault: true)
        XCTAssertEqual(MicrophoneRouting.preferred([builtIn, one, two], configuredID: builtIn.id, automaticBluetooth: true), two)
        XCTAssertEqual(MicrophoneRouting.preferred([builtIn, one, two], configuredID: one.id, automaticBluetooth: true), one)
        XCTAssertEqual(MicrophoneRouting.preferred([builtIn, one], configuredID: builtIn.id, automaticBluetooth: false), builtIn)
        XCTAssertNil(MicrophoneRouting.preferred([builtIn], configuredID: "missing", automaticBluetooth: false))
    }

    @MainActor
    func testLiveBluetoothSwitchKeepsSingleRecordingAndFrozenFolder() async throws {
        let fixture = try await PipelineFixture()
        try await fixture.start()
        let id = fixture.model.session?.id
        let folder = fixture.model.session?.configuration.folderBookmark
        fixture.microphone.devices.append(Microphone(id: "bt", name: "Bluetooth", isBluetooth: true))
        fixture.microphone.onDevicesChanged?()
        XCTAssertEqual(fixture.recorder.switches, ["bt"])
        XCTAssertEqual(fixture.model.actualMicrophoneID, "bt")
        XCTAssertEqual(fixture.model.session?.id, id)
        XCTAssertEqual(fixture.model.session?.configuration.folderBookmark, folder)
        XCTAssertEqual(fixture.recorder.starts, 1)
        fixture.stop()
        try await fixture.wait { !fixture.model.isBusy }
        XCTAssertEqual(fixture.model.history.count, 1)
    }

    @MainActor
    func testBrowserPromptDoesNotRecordUntilClickedAndNeverAutoUploadsOrPastes() async throws {
        let fixture = try await PipelineFixture()
        fixture.browser.onOutputsChanged?([browser])
        XCTAssertEqual(fixture.model.browserSuggestion, browser)
        XCTAssertEqual(fixture.browser.requests, 0)
        XCTAssertEqual(fixture.recorder.starts, 0)
        fixture.model.recordSuggestedBrowser(browser)
        try await fixture.wait { fixture.model.phase == .recording }
        XCTAssertEqual(fixture.browser.requests, 1)
        XCTAssertEqual(fixture.microphone.requests, 0)
        XCTAssertEqual(fixture.recorder.device, "browser:test.browser")
        fixture.stop()
        try await fixture.wait { !fixture.model.isBusy }
        XCTAssertEqual(fixture.transcriber.calls, 0)
        XCTAssertEqual(fixture.inserter.calls, 0)
        XCTAssertEqual(fixture.model.history.count, 1)
        XCTAssertEqual(fixture.model.history.first?.sourceLabel, "Test Browser · Browser-Audio")
        XCTAssertNotNil(fixture.model.history.first?.duration)
        XCTAssertNil(fixture.model.browserSuggestion)
    }

    @MainActor
    func testDeniedBrowserPermissionCreatesNoCaptureOrJournal() async throws {
        let fixture = try await PipelineFixture()
        fixture.browser.granted = false
        fixture.browser.onOutputsChanged?([browser])
        fixture.model.recordSuggestedBrowser(browser)
        try await fixture.wait { !fixture.model.isBusy }
        XCTAssertEqual(fixture.recorder.starts, 0)
        XCTAssertTrue(fixture.model.history.isEmpty)
        XCTAssertEqual(fixture.transcriber.calls, 0)
    }
}
