import XCTest
@testable import DictationBar

final class AudioAvailabilityTests: XCTestCase {
    @MainActor
    func testRecordingIsUnavailableWithAnExplicitReason() async {
        let availability = UnavailableAudioService().availability

        XCTAssertEqual(availability, .notImplemented)
        XCTAssertFalse(availability.isAvailable)
        XCTAssertEqual(availability.title, "Noch nicht verfügbar")
    }
}
