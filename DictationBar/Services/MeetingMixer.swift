import AVFoundation

/// Mixes system audio and microphone onto one host-time axis and returns a
/// limited mono sum in Float32 48 kHz for PCMRecordingWriter.
/// Not thread-safe: the meeting driver calls it on its serial queue.
final class MeetingMixer {
    enum Source: Int, CaseIterable { case system, microphone }

    // ponytail: fixed tolerances from the plan; tune after real one-hour recordings.
    private static let rate = 48_000.0
    private static let realignFrames = 960 // 20 ms
    private static let stallSeconds = 0.5
    private static let gain: Float = 0.7
    private static let limit: Float = 0.8912 // −1 dBFS

    private let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
    private let start: Double
    private let lanes: [Lane]
    /// Frames already returned; every lane's `pending` begins at this index.
    private var emitted = 0

    private final class Lane {
        var converter: AVAudioConverter?
        var pending: [Float] = []
        var lastEnd: Double
        init(lastEnd: Double) { self.lastEnd = lastEnd }
    }

    init(startHostTime: Double) {
        start = startHostTime
        lanes = Source.allCases.map { _ in Lane(lastEnd: startHostTime) }
    }

    /// Places `buffer` (any PCM format) at `hostTime`, in host-clock seconds.
    func append(_ buffer: AVAudioPCMBuffer, hostTime: Double, source: Source) throws {
        guard buffer.frameLength > 0, buffer.format.sampleRate > 0 else { return }
        let lane = lanes[source.rawValue]
        var samples = try convert(buffer, lane: lane)
        let target = Int(((hostTime - start) * Self.rate).rounded())
        let end = emitted + lane.pending.count
        // Small offsets stay contiguous; beyond 20 ms a gap becomes silence and
        // an overlap is dropped. This also absorbs drift between the two clocks.
        if target - end > Self.realignFrames {
            lane.pending += repeatElement(0, count: target - end)
        } else if end - target > Self.realignFrames {
            samples.removeFirst(min(end - target, samples.count))
        }
        lane.pending += samples
        lane.lastEnd = max(lane.lastEnd, hostTime + Double(buffer.frameLength) / buffer.format.sampleRate)
    }

    /// Mixes up to the point both sources reached. A source without data for
    /// 0.5 s behind the newest source counts as silent, so it never holds back the
    /// other. Measured on data time, so a stalled capture queue drops nothing.
    func mix() -> AVAudioPCMBuffer? {
        let newest = lanes.map(\.lastEnd).max()!
        let frames = lanes.filter { newest - $0.lastEnd <= Self.stallSeconds }.map(\.pending.count).min()!
        return output(frames)
    }

    /// Returns everything still pending, padding the shorter source with silence.
    func finish() -> AVAudioPCMBuffer? { output(lanes.map(\.pending.count).max()!) }

    private func output(_ frames: Int) -> AVAudioPCMBuffer? {
        guard frames > 0, let result = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)) else {
            return nil
        }
        result.frameLength = AVAudioFrameCount(frames)
        let out = result.floatChannelData![0]
        for index in 0..<frames { out[index] = 0 }
        for lane in lanes {
            for (index, sample) in lane.pending.prefix(frames).enumerated() { out[index] += sample }
            lane.pending.removeFirst(min(frames, lane.pending.count))
        }
        for index in 0..<frames { out[index] = min(max(out[index] * Self.gain, -Self.limit), Self.limit) }
        emitted += frames
        return result
    }

    private func convert(_ buffer: AVAudioPCMBuffer, lane: Lane) throws -> [Float] {
        if buffer.format == format {
            return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        }
        // A new source format (e.g. Bluetooth switching to 16 kHz) gets a fresh converter.
        if lane.converter?.inputFormat != buffer.format {
            guard let converter = AVAudioConverter(from: buffer.format, to: format) else {
                throw PCMRecordingWriterError.conversion
            }
            converter.downmix = true
            converter.primeMethod = .none
            lane.converter = converter
        }
        guard let converter = lane.converter else { throw PCMRecordingWriterError.conversion }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * Self.rate / buffer.format.sampleRate) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            throw PCMRecordingWriterError.conversion
        }
        var result: [Float] = []
        var supplied = false
        while true {
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, inputStatus in
                if supplied { inputStatus.pointee = .noDataNow; return nil }
                supplied = true
                inputStatus.pointee = .haveData
                return buffer
            }
            if let error { throw error }
            result += UnsafeBufferPointer(start: output.floatChannelData![0], count: Int(output.frameLength))
            switch status {
            case .haveData: if output.frameLength == 0 { return result }
            case .inputRanDry, .endOfStream: return result
            case .error: throw PCMRecordingWriterError.conversion
            @unknown default: throw PCMRecordingWriterError.conversion
            }
        }
    }
}
