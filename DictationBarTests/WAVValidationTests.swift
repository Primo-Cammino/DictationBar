import XCTest
@testable import DictationBar

final class WAVValidationTests: XCTestCase {
    func testPCM16Mono48kIsAcceptedButEmptyAndWrongFormatAreNotSaved() throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let url = f.folder.appendingPathComponent("fixture.wav")
        try LocalStoreFixture.wav().write(to: url)
        XCTAssertEqual(try WAVValidator.inspect(url).frames, 480)
        for invalid in [Data(), LocalStoreFixture.wav(frames: 0), LocalStoreFixture.wav(sampleRate: 44_100), LocalStoreFixture.wav(bits: 8)] {
            try invalid.write(to: url)
            XCTAssertThrowsError(try WAVValidator.inspect(url))
        }
    }
}
