import AVFoundation
import XCTest
@testable import DictationBar

final class PermissionMappingTests: XCTestCase {
    @MainActor
    func testKnownMicrophoneStatesKeepTheirMeaning() async {
        let cases: [(AVAuthorizationStatus, MicrophonePermission, String)] = [
            (.notDetermined, .notDetermined, "Noch nicht angefragt"),
            (.restricted, .restricted, "Durch macOS eingeschränkt"),
            (.denied, .denied, "Nicht erlaubt"),
            (.authorized, .authorized, "Erlaubt")
        ]

        for (nativeStatus, expected, title) in cases {
            let reader = NativePermissionReader {
                nativeStatus.rawValue
            }

            let snapshot = reader.snapshot()

            XCTAssertEqual(snapshot.microphone, expected)
            XCTAssertEqual(snapshot.microphone.title, title)
        }
    }

    @MainActor
    func testUnknownMicrophoneValueDoesNotClaimAuthorization() async {
        let reader = NativePermissionReader { Int.max }

        XCTAssertEqual(reader.snapshot().microphone, .unknown)
        XCTAssertEqual(reader.snapshot().microphone.title, "Unbekannt")
    }

    @MainActor
    func testAuthorizedMicrophoneDoesNotConfirmSystemAudio() async {
        let reader = NativePermissionReader {
            AVAuthorizationStatus.authorized.rawValue
        }

        XCTAssertEqual(reader.snapshot().systemAudio, .notVerified)
        XCTAssertEqual(reader.snapshot().systemAudio.title, "Noch nicht geprüft")
    }

    @MainActor
    func testReadingAgainReflectsChangedAuthorization() async {
        var status = AVAuthorizationStatus.notDetermined
        let reader = NativePermissionReader { status.rawValue }

        XCTAssertEqual(reader.snapshot().microphone, .notDetermined)

        status = .denied

        XCTAssertEqual(reader.snapshot().microphone, .denied)
        XCTAssertEqual(reader.snapshot().systemAudio, .notVerified)
    }
}
