import AVFoundation
import Darwin
import XCTest
@testable import DictationBar

final class PCMRecordingWriterTests: XCTestCase {
    func testDifferentSourceFormatsKeepBothSegmentsInOnePCM16Mono48kWAV() throws {
        let fixture = try LocalStoreFixture(); defer { fixture.cleanup() }
        let paths = try reservedPaths(in: fixture)
        let writer = try PCMRecordingWriter(paths: paths)
        try writer.append(buffer(rate: 48_000, frames: 4_800, value: 0.25))
        try writer.append(buffer(rate: 16_000, frames: 1_600, value: -0.5))
        try writer.close()

        let info = try WAVValidator.inspect(paths.staging)
        XCTAssertEqual(info.frames, writer.writtenFrames)
        XCTAssertEqual(info.duration, 0.2, accuracy: 0.001)
        let file = try AVAudioFile(forReading: paths.staging)
        let samples = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: samples)
        let channel = try XCTUnwrap(samples.floatChannelData?[0])
        // Sample safely inside each segment, away from converter boundaries.
        XCTAssertEqual(channel[2_400], 0.25, accuracy: 0.01)
        XCTAssertEqual(channel[7_200], -0.5, accuracy: 0.01)
        let bytes = try Data(contentsOf: paths.staging)
        XCTAssertEqual(bytes.count, 44 + Int(writer.writtenFrames) * 2)
        XCTAssertEqual(littleEndian32(bytes, at: 4), UInt32(bytes.count - 8))
        XCTAssertEqual(littleEndian32(bytes, at: 40), UInt32(bytes.count - 44))
    }

    func testStereoSourceIsDownmixedToMono() throws {
        let fixture = try LocalStoreFixture(); defer { fixture.cleanup() }
        let paths = try reservedPaths(in: fixture)
        let writer = try PCMRecordingWriter(paths: paths)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let source = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        source.frameLength = 480
        for frame in 0..<480 {
            source.floatChannelData![0][frame] = 0.25
            source.floatChannelData![1][frame] = 0.25
        }
        try writer.append(source)
        try writer.close()
        let file = try AVAudioFile(forReading: paths.staging)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        let samples = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 480))
        try file.read(into: samples)
        XCTAssertEqual(samples.floatChannelData![0][240], 0.25, accuracy: 0.01)
    }

    func testZeroFrameCloseWritesValidEmptyHeaderAndIsIdempotent() throws {
        let fixture = try LocalStoreFixture(); defer { fixture.cleanup() }
        let paths = try reservedPaths(in: fixture)
        let writer = try PCMRecordingWriter(paths: paths)
        try writer.append(buffer(rate: 48_000, frames: 0, value: 0))
        try writer.close()
        try writer.close()
        XCTAssertEqual(writer.writtenFrames, 0)
        XCTAssertEqual(try Data(contentsOf: paths.staging), LocalStoreFixture.wav(frames: 0))
        XCTAssertEqual(try AVAudioFile(forReading: paths.staging).length, 0)
    }

    func testExistingUnreservedFileCannotBeOverwritten() throws {
        let fixture = try LocalStoreFixture(); defer { fixture.cleanup() }
        let staging = fixture.folder.appendingPathComponent("collision.wav")
        let original = Data("retain existing bytes".utf8)
        try original.write(to: staging)
        XCTAssertThrowsError(try PCMRecordingWriter(paths: RecordingPaths(staging: staging, final: staging)))
        XCTAssertEqual(try Data(contentsOf: staging), original)
    }

    func testNonemptyReservationCannotBeReleasedOrOverwritten() throws {
        let fixture = try LocalStoreFixture(); defer { fixture.cleanup() }
        let paths = try reservedPaths(in: fixture)
        let original = Data("retain reservation collision".utf8)
        try original.write(to: paths.staging)
        XCTAssertThrowsError(try PCMRecordingWriter(paths: paths))
        XCTAssertEqual(try Data(contentsOf: paths.staging), original)
    }

    func testAppendAfterCloseIsRejectedAndDoesNotChangeSavedBytes() throws {
        let fixture = try LocalStoreFixture(); defer { fixture.cleanup() }
        let paths = try reservedPaths(in: fixture)
        let writer = try PCMRecordingWriter(paths: paths)
        try writer.append(buffer(rate: 48_000, frames: 480, value: 0.25))
        try writer.close()
        let saved = try Data(contentsOf: paths.staging)
        XCTAssertThrowsError(try writer.append(buffer(rate: 16_000, frames: 160, value: -0.5)))
        XCTAssertEqual(try Data(contentsOf: paths.staging), saved)
    }

    private func buffer(rate: Double, frames: AVAudioFrameCount, value: Float) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1))
        let result = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(1, frames)))
        result.frameLength = frames
        for frame in 0..<Int(frames) { result.floatChannelData![0][frame] = value }
        return result
    }

    private func reservedPaths(in fixture: LocalStoreFixture) throws -> RecordingPaths {
        let staging = fixture.folder.appendingPathComponent("recording.partial.wav")
        let descriptor = Darwin.open(staging.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw CocoaError(.fileWriteUnknown) }
        return RecordingPaths(staging: staging, final: fixture.folder.appendingPathComponent("recording.wav"),
                              reservation: StagingReservation(inode: info.st_ino, device: info.st_dev))
    }

    private func littleEndian32(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | (UInt32(data[offset + $1]) << ($1 * 8)) }
    }
}
