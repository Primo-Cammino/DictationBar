import AVFoundation
import XCTest
@testable import DictationBar

final class MeetingMixerTests: XCTestCase {
    private let start = 1_000.0

    func testBothSourcesAreAudibleInTheMix() throws {
        let mixer = MeetingMixer(startHostTime: start)
        var out: [Float] = []
        for chunk in 0..<10 {
            let time = start + Double(chunk) * 0.1
            let offset = chunk * 4_800
            try mixer.append(buffer(frames: 4_800) { 0.5 * sine(440, offset + $0) }, hostTime: time, source: .system)
            try mixer.append(buffer(frames: 4_800) { 0.5 * sine(1_000, offset + $0) }, hostTime: time, source: .microphone)
            out += samples(mixer.mix(upTo: time + 0.1))
        }
        out += samples(mixer.finish())
        XCTAssertEqual(out.count, 48_000)
        XCTAssertEqual(correlation(out, 440), 0.35, accuracy: 0.02)
        XCTAssertEqual(correlation(out, 1_000), 0.35, accuracy: 0.02)
    }

    func testGapBecomesSilenceOfThatSourceOnly() throws {
        let mixer = MeetingMixer(startHostTime: start)
        var out: [Float] = []
        for chunk in 0..<10 {
            let time = start + Double(chunk) * 0.1
            try mixer.append(buffer(frames: 4_800) { _ in 0.25 }, hostTime: time, source: .system)
            if chunk != 3 && chunk != 4 {
                try mixer.append(buffer(frames: 4_800) { _ in 0.5 }, hostTime: time, source: .microphone)
            }
            out += samples(mixer.mix(upTo: time + 0.1))
        }
        out += samples(mixer.finish())
        XCTAssertEqual(out.count, 48_000)
        XCTAssertEqual(out[9_600], 0.525, accuracy: 0.001)
        XCTAssertEqual(out[19_200], 0.175, accuracy: 0.001)
        XCTAssertEqual(out[33_600], 0.525, accuracy: 0.001)
    }

    func testSixteenKilohertzSourceIsResampledWithoutLengthDrift() throws {
        let mixer = MeetingMixer(startHostTime: start)
        var out: [Float] = []
        for chunk in 0..<10 {
            let time = start + Double(chunk) * 0.1
            try mixer.append(buffer(frames: 4_800) { _ in 0.1 }, hostTime: time, source: .system)
            try mixer.append(buffer(rate: 16_000, frames: 1_600) { _ in 0.1 }, hostTime: time, source: .microphone)
            out += samples(mixer.mix(upTo: time + 0.1))
        }
        out += samples(mixer.finish())
        XCTAssertEqual(Double(out.count), 48_000, accuracy: 480)
        XCTAssertEqual(out[24_000], 0.14, accuracy: 0.005)
    }

    func testSourceSilentForHalfASecondDoesNotHoldBackTheOther() throws {
        let mixer = MeetingMixer(startHostTime: start)
        for chunk in 0..<3 {
            try mixer.append(buffer(frames: 4_800) { _ in 0.25 }, hostTime: start + Double(chunk) * 0.1, source: .system)
        }
        XCTAssertTrue(samples(mixer.mix(upTo: start + 0.3)).isEmpty)
        for chunk in 3..<10 {
            try mixer.append(buffer(frames: 4_800) { _ in 0.25 }, hostTime: start + Double(chunk) * 0.1, source: .system)
        }
        let out = samples(mixer.mix(upTo: start + 1.0))
        XCTAssertEqual(out.count, 48_000)
        XCTAssertEqual(out[40_000], 0.175, accuracy: 0.001)
    }

    func testFullScaleSumStaysBelowMinusOneDBFS() throws {
        let mixer = MeetingMixer(startHostTime: start)
        try mixer.append(buffer(frames: 4_800) { _ in 1 }, hostTime: start, source: .system)
        try mixer.append(buffer(frames: 4_800) { -1 + 2 * Float($0 % 2) }, hostTime: start, source: .microphone)
        try mixer.append(buffer(frames: 4_800) { _ in -1 }, hostTime: start + 0.1, source: .system)
        try mixer.append(buffer(frames: 4_800) { _ in -1 }, hostTime: start + 0.1, source: .microphone)
        let out = samples(mixer.finish())
        let peak = out.map(abs).max() ?? 0
        XCTAssertLessThanOrEqual(peak, 0.8913)
        XCTAssertGreaterThan(peak, 0.88)
    }

    func testHundredPPMDriftStaysWithinTwentyMilliseconds() throws {
        let mixer = MeetingMixer(startHostTime: start)
        // The microphone clock runs 100 ppm fast: 4,800 of its frames span less host time.
        let microphoneChunk = 4_800 / 48_004.8
        let chunks = 6_000 // ten minutes
        let markerTime = start + Double(chunks - 1) * microphoneChunk
        var emitted = 0
        var marker: Int?
        func collect(_ buffer: AVAudioPCMBuffer?) {
            let block = samples(buffer)
            if marker == nil, let index = block.firstIndex(where: { $0 != 0 }) { marker = emitted + index }
            emitted += block.count
        }
        for chunk in 0..<chunks {
            let time = start + Double(chunk) * 0.1
            try mixer.append(buffer(frames: 4_800) { _ in 0 }, hostTime: time, source: .system)
            let last = chunk == chunks - 1
            try mixer.append(buffer(frames: 4_800) { last && $0 == 0 ? 0.5 : 0 },
                             hostTime: start + Double(chunk) * microphoneChunk, source: .microphone)
            collect(mixer.mix(upTo: time + 0.1))
        }
        collect(mixer.finish())
        let expected = Int(((markerTime - start) * 48_000).rounded())
        let found = try XCTUnwrap(marker)
        XCTAssertLessThanOrEqual(abs(found - expected), 960)
    }

    func testBufferBeforeStartIsDropped() throws {
        let mixer = MeetingMixer(startHostTime: start)
        try mixer.append(buffer(frames: 4_800) { _ in 0.9 }, hostTime: start - 1, source: .system)
        for chunk in 0..<5 {
            let time = start + Double(chunk) * 0.1
            try mixer.append(buffer(frames: 4_800) { _ in 0.25 }, hostTime: time, source: .system)
            try mixer.append(buffer(frames: 4_800) { _ in 0.25 }, hostTime: time, source: .microphone)
        }
        let out = samples(mixer.finish())
        XCTAssertEqual(out.count, 24_000)
        XCTAssertEqual(out[0], 0.35, accuracy: 0.001)
        XCTAssertEqual(out.max() ?? 0, 0.35, accuracy: 0.001)
    }

    private func buffer(rate: Double = 48_000, frames: Int, _ sample: (Int) -> Float) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        result.frameLength = AVAudioFrameCount(frames)
        for index in 0..<frames { result.floatChannelData![0][index] = sample(index) }
        return result
    }

    private func samples(_ buffer: AVAudioPCMBuffer?) -> [Float] {
        guard let buffer else { return [] }
        XCTAssertEqual(buffer.format.sampleRate, 48_000)
        XCTAssertEqual(buffer.format.channelCount, 1)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    private func sine(_ frequency: Double, _ index: Int) -> Float {
        Float(sin(2 * .pi * frequency * Double(index) / 48_000))
    }

    /// Amplitude of `frequency` in `signal`.
    private func correlation(_ signal: [Float], _ frequency: Double) -> Float {
        var sum: Float = 0
        for (index, value) in signal.enumerated() { sum += value * sine(frequency, index) }
        return 2 * sum / Float(signal.count)
    }
}
