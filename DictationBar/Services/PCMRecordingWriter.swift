import AVFoundation
import CoreMedia
import Darwin
import Foundation

enum PCMRecordingWriterError: Error {
    case closed, invalidBuffer, conversion, tooLarge
}

/// Single-queue writer shared by microphone and browser capture. Only this
/// descriptor writes the WAV; source changes retain both the file and its bytes.
final class PCMRecordingWriter {
    private let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48_000,
                                       channels: 1, interleaved: true)!
    private var handle: FileHandle?
    private var converter: AVAudioConverter?
    private var sourceFormat: AVAudioFormat?
    private var appendFailed = false
    private var expectedFrames: Double = 0
    private(set) var writtenFrames: Int64 = 0
    private var syncedFrames: Int64 = 0

    init(paths: RecordingPaths) throws {
        guard let reservation = paths.reservation else { throw LocalStoreError.collision }
        try reservation.release(at: paths.staging)
        // The reservation release is followed by exclusive creation. A new file
        // arriving in that interval is retained, including a symlink collision.
        let descriptor = Darwin.open(paths.staging.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            if errno == EEXIST { throw LocalStoreError.collision }
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Self.header(dataBytes: 0))
            self.handle = handle
        } catch {
            try? handle.close()
            throw error
        }
    }

    func append(_ sampleBuffer: CMSampleBuffer) throws {
        guard handle != nil, !appendFailed else { throw PCMRecordingWriterError.closed }
        do {
            guard CMSampleBufferDataIsReady(sampleBuffer),
                  let description = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let basic = CMAudioFormatDescriptionGetStreamBasicDescription(description),
                  basic.pointee.mFormatID == kAudioFormatLinearPCM else {
                throw PCMRecordingWriterError.invalidBuffer
            }
            let frames = CMSampleBufferGetNumSamples(sampleBuffer)
            guard frames >= 0, frames <= Int(Int32.max) else { throw PCMRecordingWriterError.invalidBuffer }
            if frames == 0 { return }
            let source = AVAudioFormat(cmAudioFormatDescription: description)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(frames)) else {
                throw PCMRecordingWriterError.invalidBuffer
            }
            buffer.frameLength = AVAudioFrameCount(frames)
            guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0,
                    frameCount: Int32(frames), into: buffer.mutableAudioBufferList) == noErr else {
                throw PCMRecordingWriterError.invalidBuffer
            }
            try append(buffer)
        } catch {
            appendFailed = true
            throw error
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) throws {
        guard handle != nil, !appendFailed else { throw PCMRecordingWriterError.closed }
        do {
            if buffer.frameLength == 0 { return }
            guard buffer.format.sampleRate.isFinite, buffer.format.sampleRate > 0,
                  buffer.format.channelCount > 0 else { throw PCMRecordingWriterError.invalidBuffer }
            if sourceFormat?.isEqual(buffer.format) != true {
                // Finish the old resampler before accepting the new source's
                // rate/layout. Recreating it prevents stale format state.
                try drainConverter()
                guard let replacement = AVAudioConverter(from: buffer.format, to: format) else {
                    throw PCMRecordingWriterError.conversion
                }
                replacement.downmix = true
                replacement.primeMethod = .none
                converter = replacement
                sourceFormat = buffer.format
            }
            guard let converter else { throw PCMRecordingWriterError.conversion }
            expectedFrames += Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
            guard expectedFrames.isFinite, expectedFrames <= Double((UInt32.max - 36) / 2) else {
                throw PCMRecordingWriterError.tooLarge
            }
            var supplied = false
            try convert(converter) { _, status in
                if !supplied {
                    supplied = true
                    status.pointee = .haveData
                    return buffer
                }
                status.pointee = .noDataNow
                return nil
            }
        } catch {
            appendFailed = true
            throw error
        }
    }

    /// Even after a conversion/write error, repair the header for bytes already
    /// written and synchronize before the driver announces capture completion.
    func close() throws {
        guard let handle else { return }
        var firstError: Error?
        if !appendFailed {
            do { try drainConverter() } catch { firstError = error }
        }
        converter = nil
        sourceFormat = nil
        do {
            let size = try handle.seekToEnd()
            guard size >= 44, size - 44 <= UInt64(UInt32.max - 36) else {
                throw PCMRecordingWriterError.tooLarge
            }
            let dataBytes = (size - 44) / 2 * 2
            // A partial failed filesystem write can end between sample frames.
            // Only complete PCM frames are included in the repaired WAV.
            if dataBytes + 44 != size { try handle.truncate(atOffset: dataBytes + 44) }
            writtenFrames = Int64(dataBytes / 2)
            try handle.seek(toOffset: 0)
            try handle.write(contentsOf: Self.header(dataBytes: UInt32(dataBytes)))
        } catch { if firstError == nil { firstError = error } }
        do { try handle.synchronize() } catch { if firstError == nil { firstError = error } }
        do { try handle.close() } catch { if firstError == nil { firstError = error } }
        self.handle = nil
        if let firstError { throw firstError }
    }

    private func drainConverter() throws {
        guard let converter else { return }
        try convert(converter, draining: true) { _, status in
            status.pointee = .endOfStream
            return nil
        }
        // AVAudioConverter may emit resampler tail padding at EOS. Keep the
        // source duration, so a format switch adds no artificial silence.
        let expected = Int64(expectedFrames.rounded())
        if writtenFrames > expected, let handle {
            try handle.truncate(atOffset: UInt64(44 + expected * 2))
            try handle.seekToEnd()
            writtenFrames = expected
        }
        converter.reset()
        self.converter = nil
        sourceFormat = nil
    }

    private func convert(_ converter: AVAudioConverter, draining: Bool = false,
                         input: @escaping AVAudioConverterInputBlock) throws {
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_096) else {
            throw PCMRecordingWriterError.conversion
        }
        while true {
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error, withInputFrom: input)
            // Conversion may produce valid final frames before reporting EOS.
            if output.frameLength > 0 { try write(output) }
            if let error { throw error }
            switch status {
            case .haveData:
                guard output.frameLength > 0 else { throw PCMRecordingWriterError.conversion }
            case .inputRanDry:
                if draining { throw PCMRecordingWriterError.conversion }
                return
            case .endOfStream:
                return
            case .error:
                throw PCMRecordingWriterError.conversion
            @unknown default:
                throw PCMRecordingWriterError.conversion
            }
        }
    }

    private func write(_ buffer: AVAudioPCMBuffer) throws {
        guard let handle else { throw PCMRecordingWriterError.closed }
        let byteCount = Int(buffer.frameLength) * 2
        guard writtenFrames * 2 + Int64(byteCount) <= Int64(UInt32.max - 36),
              let bytes = buffer.audioBufferList.pointee.mBuffers.mData else {
            throw PCMRecordingWriterError.tooLarge
        }
        try handle.write(contentsOf: Data(bytes: bytes, count: byteCount))
        writtenFrames += Int64(buffer.frameLength)
        // About every 10 s of audio, flush to disk so a power loss keeps the
        // samples; RecordingStore.recover repairs the still-empty header.
        if writtenFrames - syncedFrames >= 480_000 {
            try handle.synchronize()
            syncedFrames = writtenFrames
        }
    }

    /// The writer's 44-byte PCM16 mono 48 kHz header, also used by recovery.
    static func header(dataBytes: UInt32) -> Data {
        var result = Data()
        func ascii(_ text: String) { result.append(contentsOf: text.utf8) }
        func u16(_ value: UInt16) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { result.append(contentsOf: $0) }
        }
        func u32(_ value: UInt32) {
            var littleEndian = value.littleEndian
            withUnsafeBytes(of: &littleEndian) { result.append(contentsOf: $0) }
        }
        ascii("RIFF"); u32(36 + dataBytes); ascii("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(48_000); u32(96_000); u16(2); u16(16)
        ascii("data"); u32(dataBytes)
        return result
    }
}
