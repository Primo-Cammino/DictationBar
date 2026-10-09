import XCTest
@testable import DictationBar

final class StatusModelTests: XCTestCase {
    @MainActor
    func testAuthorizedMicrophoneStillLeavesRecordingUnavailable() async {
        let model = makeModel(microphone: .authorized)

        XCTAssertEqual(model.permissions.microphone, .authorized)
        XCTAssertEqual(model.permissions.systemAudio, .notVerified)
        XCTAssertEqual(model.recordingAvailability, .notImplemented)
        XCTAssertFalse(model.recordingAvailability.isAvailable)
    }

    @MainActor
    func testRefreshDisplaysExternalMicrophoneChange() async {
        let reader = MutablePermissionReader(microphone: .notDetermined)
        let model = StatusModel(
            permissionReader: reader,
            audioAvailabilityService: UnavailableAudioService()
        )

        XCTAssertEqual(model.permissions.microphone, .notDetermined)

        reader.microphone = .authorized
        model.refresh()

        XCTAssertEqual(model.permissions.microphone, .authorized)
        XCTAssertEqual(model.permissions.systemAudio, .notVerified)
        XCTAssertFalse(model.recordingAvailability.isAvailable)
    }

    @MainActor
    func testRepeatedRefreshKeepsRecordingUnavailable() async {
        let model = makeModel(microphone: .authorized)

        for _ in 0..<3 {
            model.refresh()

            XCTAssertEqual(model.permissions.microphone, .authorized)
            XCTAssertEqual(model.permissions.systemAudio, .notVerified)
            XCTAssertEqual(model.recordingAvailability, .notImplemented)
        }
    }

    @MainActor
    func testRefreshKeepsRestrictedDeniedAndUnknownDistinct() async {
        let reader = MutablePermissionReader(microphone: .authorized)
        let model = StatusModel(
            permissionReader: reader,
            audioAvailabilityService: UnavailableAudioService()
        )

        for status in [MicrophonePermission.restricted, .denied, .unknown] {
            reader.microphone = status
            model.refresh()

            XCTAssertEqual(model.permissions.microphone, status)
            XCTAssertEqual(model.permissions.systemAudio, .notVerified)
            XCTAssertFalse(model.recordingAvailability.isAvailable)
        }
    }

    @MainActor
    private func makeModel(microphone: MicrophonePermission) -> StatusModel {
        StatusModel(
            permissionReader: MutablePermissionReader(microphone: microphone),
            audioAvailabilityService: UnavailableAudioService()
        )
    }
}

@MainActor
private final class MutablePermissionReader: PermissionReading {
    var microphone: MicrophonePermission

    init(microphone: MicrophonePermission) {
        self.microphone = microphone
    }

    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(microphone: microphone, systemAudio: .notVerified)
    }
}
