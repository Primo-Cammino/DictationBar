import XCTest
@testable import DictationBar

final class BluetoothMicrophoneTests: XCTestCase {
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
}
