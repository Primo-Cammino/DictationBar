@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import XCTest
@testable import DictationBar

@MainActor
final class NativeMeetingCaptureDriverTests: XCTestCase {
    func testBothSourcesAreMixedAndFirstConfirmedStopClosesTheFile() async throws {
        let h = try await MeetingDriverHarness(); defer { h.fixture.cleanup() }
        try await h.start()
        let base = hostNow()
        for step in 0..<2 {
            h.system.sample(try sample(value: 8_192), at: base + Double(step) * 0.01)
            h.microphone.sample(try sample(value: 8_192), at: base + Double(step) * 0.01)
        }
        let stopping = Task { try await h.service.stop() }
        try await wait { h.system.stops == 1 && h.microphone.stops == 1 }
        h.system.completeStop(nil)
        let completion = try await stopping.value
        XCTAssertFalse(completion.interrupted)
        XCTAssertFalse(h.service.isActive)
        let samples = try pcm(h.paths.staging)
        XCTAssertEqual(samples.count, 960)
        XCTAssertEqual(samples[240], 0.35, accuracy: 0.001)
        XCTAssertEqual(samples[720], 0.35, accuracy: 0.001)

        // Late callbacks after the end change nothing.
        let saved = try Data(contentsOf: h.paths.staging)
        h.system.sample(try sample(value: -8_192), at: base + 0.02)
        h.microphone.completeStop(nil)
        h.microphone.confirmStopped()
        await h.settle()
        XCTAssertEqual(try Data(contentsOf: h.paths.staging), saved)
        XCTAssertEqual(h.completions.count, 1)
        XCTAssertEqual(h.microphone.releases, 1)
    }

    func testMicrophoneThatNeverStartsStopsSystemAudioAndLeavesNoOpenFile() async throws {
        let h = try await MeetingDriverHarness(deadlineNanoseconds: 50_000_000); defer { h.fixture.cleanup() }
        let starting = Task { try await h.service.startMeeting(microphoneID: "mic", paths: h.paths) }
        try await wait { h.system.starts == 1 && h.microphone.starts == 1 }
        h.system.completeStart(nil)
        do { try await starting.value; XCTFail("Expected timeout") }
        catch { guard case CaptureFailure.timeout = error else { XCTFail("Expected timeout, got \(error)"); return } }
        try await wait { !h.service.isActive }
        XCTAssertEqual(h.system.stops, 1)
        XCTAssertEqual(h.failedStarts, 1)
        XCTAssertEqual(try Data(contentsOf: h.paths.staging).count, 44)
        // A late microphone start is stopped right away instead of recording unseen.
        h.microphone.completeStart(nil)
        try await wait { h.microphone.stops == 1 }
        XCTAssertEqual(h.completions.count, 0)
    }

    func testMicrophoneThatCannotBeOpenedFailsStartAndReleasesSystemAudio() async throws {
        let h = try await MeetingDriverHarness(microphoneLookupFails: true); defer { h.fixture.cleanup() }
        let starting = Task { try await h.service.startMeeting(microphoneID: "mic", paths: h.paths) }
        try await expectStartFailure(starting)
        try await wait { h.system.releases == 1 }
        XCTAssertEqual(h.failedStarts, 1)
        XCTAssertEqual(h.system.starts + h.microphone.starts, 0)
        XCTAssertFalse(h.service.isActive)
    }

    func testMicrophoneStartErrorFailsStartAndStopsLateSystemAudio() async throws {
        try await assertMicrophoneFailureDuringStart { $0.completeStart(CaptureFailure.start) }
    }

    func testMicrophoneEndingBeforeStartFailsStartAndStopsLateSystemAudio() async throws {
        try await assertMicrophoneFailureDuringStart { $0.confirmStopped() }
    }

    func testLostMicrophoneKeepsRecordingSystemAudio() async throws {
        let h = try await MeetingDriverHarness(); defer { h.fixture.cleanup() }
        try await h.start()
        let base = hostNow()
        h.system.sample(try sample(value: 8_192), at: base)
        h.microphone.sample(try sample(value: 8_192), at: base)
        h.microphone.confirmStopped()
        try await wait { h.lost == [.microphone] }
        XCTAssertTrue(h.service.isActive)
        XCTAssertEqual(h.microphone.releases, 1)
        h.system.sample(try sample(value: 8_192), at: base + 0.01)
        h.system.sample(try sample(value: 8_192), at: base + 0.02)
        let stopping = Task { try await h.service.stop() }
        try await wait { h.system.stops == 1 }
        XCTAssertEqual(h.microphone.stops, 0)
        h.system.completeStop(nil)
        let completion = try await stopping.value
        XCTAssertFalse(completion.interrupted)
        XCTAssertEqual(h.interruptions, 0)
        let samples = try pcm(h.paths.staging)
        XCTAssertEqual(samples.count, 1_440)
        XCTAssertEqual(samples[240], 0.35, accuracy: 0.001)
        XCTAssertEqual(samples[960], 0.175, accuracy: 0.001)
    }

    func testFailedSystemAudioKeepsRecordingMicrophone() async throws {
        let h = try await MeetingDriverHarness(); defer { h.fixture.cleanup() }
        try await h.start()
        let base = hostNow()
        h.system.sample(try sample(value: 8_192), at: base)
        h.microphone.sample(try sample(value: 8_192), at: base)
        h.system.confirmStopped()
        try await wait { h.lost == [.system] }
        h.microphone.sample(try sample(value: 8_192), at: base + 0.01)
        let stopping = Task { try await h.service.stop() }
        try await wait { h.microphone.stops == 1 }
        h.microphone.completeStop(nil)
        let completion = try await stopping.value
        XCTAssertFalse(completion.interrupted)
        XCTAssertEqual(try pcm(h.paths.staging).count, 960)
        XCTAssertEqual(h.interruptions, 0)
    }

    func testLosingBothSourcesEndsTheMeetingAsInterrupted() async throws {
        let h = try await MeetingDriverHarness(); defer { h.fixture.cleanup() }
        try await h.start()
        let base = hostNow()
        h.system.sample(try sample(value: 8_192), at: base)
        h.microphone.sample(try sample(value: 8_192), at: base)
        h.microphone.confirmStopped()
        h.system.confirmStopped()
        try await wait { !h.service.isActive }
        XCTAssertEqual(h.lost, [.microphone])
        XCTAssertEqual(h.completions, [CaptureCompletion(interrupted: true)])
        XCTAssertEqual(h.interruptions, 1)
        XCTAssertEqual(try WAVValidator.inspect(h.paths.staging).frames, 480)
    }

    func testSourcesThatNeverConfirmStopReleaseTheGateAfterGracePeriod() async throws {
        let h = try await MeetingDriverHarness(stopGrace: .milliseconds(50)); defer { h.fixture.cleanup() }
        try await h.start()
        let base = hostNow()
        h.system.sample(try sample(value: 8_192), at: base)
        h.microphone.sample(try sample(value: 8_192), at: base)
        let completion = try await h.service.stop()
        XCTAssertFalse(completion.interrupted)
        XCTAssertFalse(h.service.isActive)
        XCTAssertEqual(h.system.stops, 1)
        XCTAssertEqual(h.microphone.stops, 1)
        XCTAssertEqual(try WAVValidator.inspect(h.paths.staging).frames, 480)
    }

    func testWriteFailureEndsMeetingAsInterrupted() async throws {
        let h = try await MeetingDriverHarness(); defer { h.fixture.cleanup() }
        try await h.start()
        h.system.sample(try sample(value: 8_192), at: hostNow())
        h.system.sample(try invalidSample(), at: hostNow())
        try await wait { h.system.stops == 1 && h.microphone.stops == 1 }
        h.microphone.completeStop(nil)
        try await wait { !h.service.isActive }
        XCTAssertEqual(h.completions, [CaptureCompletion(interrupted: true)])
        XCTAssertEqual(h.interruptions, 1)
    }

    func testStopBeforeStreamsExistCannotStartLateStreamsOrReleaseReservation() async throws {
        let h = try await MeetingDriverHarness(); defer { h.fixture.cleanup() }
        let events = MeetingDriverEvents()
        let gate = LookupGate()
        let (system, microphone) = (h.system, h.microphone)
        let driver = NativeMeetingCaptureDriver(microphoneID: "mic", paths: h.paths, queue: h.queue,
            makeStream: { source, _, sample, stopped in
                let stream = source == .system ? system : microphone
                stream.install(sample: sample, stopped: stopped)
                if source == .microphone { await gate.wait() }
                return stream
            }, event: events.record)
        driver.start()
        try await wait { gate.entered }
        driver.stop()
        await h.settle()
        XCTAssertEqual(events.failedStarts, 1)
        gate.release()
        try await wait { system.releases == 1 && microphone.releases == 1 }
        await h.settle()
        XCTAssertEqual(system.starts + microphone.starts, 0)
        XCTAssertEqual(events.failedStarts, 1)
        XCTAssertEqual(try Data(contentsOf: h.paths.staging).count, 0)
    }

    /// The microphone fails while system audio is still starting: the start fails,
    /// the file is closed empty and a late system start is stopped right away.
    private func assertMicrophoneFailureDuringStart(_ fail: (ControlledStream) -> Void) async throws {
        let h = try await MeetingDriverHarness(); defer { h.fixture.cleanup() }
        let starting = Task { try await h.service.startMeeting(microphoneID: "mic", paths: h.paths) }
        try await wait { h.system.starts == 1 && h.microphone.starts == 1 }
        fail(h.microphone)
        try await expectStartFailure(starting)
        XCTAssertEqual(h.failedStarts, 1)
        XCTAssertEqual(h.microphone.releases, 1)
        XCTAssertEqual(try Data(contentsOf: h.paths.staging).count, 44)
        h.system.completeStart(nil)
        try await wait { h.system.stops == 1 }
        XCTAssertEqual(h.completions.count, 0)
    }

    private func expectStartFailure(_ starting: Task<Void, Error>) async throws {
        do { try await starting.value; XCTFail("Expected start failure") }
        catch { guard case CaptureFailure.start = error else { XCTFail("Expected start failure, got \(error)"); return } }
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else { XCTFail("Timed out waiting for driver callback"); throw CaptureFailure.timeout }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
    }

    private func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    private func pcm(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    }

    private func sample(value: Int16) throws -> CMSampleBuffer {
        var format = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16,
            mReserved: 0)
        var description: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &format,
            layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &description), noErr)
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
            blockLength: 960, blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: 960, flags: 0, blockBufferOut: &block), noErr)
        let bytes = Array(repeating: value.littleEndian, count: 480)
        let blockBuffer = try XCTUnwrap(block)
        XCTAssertEqual(bytes.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0,
                                          dataLength: 960)
        }, noErr)
        var result: CMSampleBuffer?
        XCTAssertEqual(CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer, formatDescription: try XCTUnwrap(description), sampleCount: 480,
            presentationTimeStamp: .zero, packetDescriptions: nil, sampleBufferOut: &result), noErr)
        return try XCTUnwrap(result)
    }

    private func invalidSample() throws -> CMSampleBuffer {
        var result: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: nil,
            formatDescription: nil, sampleCount: 0, sampleTimingEntryCount: 0, sampleTimingArray: nil,
            sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &result), noErr)
        return try XCTUnwrap(result)
    }
}

@MainActor
private final class MeetingDriverHarness {
    let fixture: LocalStoreFixture
    let paths: RecordingPaths
    let queue = DispatchQueue(label: "DictationBarTests.meeting-driver")
    let system: ControlledStream
    let microphone: ControlledStream
    let service: RecordingService
    var lost: [MeetingMixer.Source] = []
    var interruptions = 0
    private let events = MeetingDriverEvents()
    var completions: [CaptureCompletion] { events.completions }
    var failedStarts: Int { events.failedStarts }

    init(deadlineNanoseconds: UInt64 = 15_000_000_000, stopGrace: DispatchTimeInterval = .seconds(5),
         microphoneLookupFails: Bool = false) async throws {
        fixture = try LocalStoreFixture()
        let entry = try fixture.entry()
        paths = try await RecordingStore(history: HistoryStore(supportURL: fixture.support))
            .prepare(entry, token: fixture.token(entry))
        let queue = queue
        let system = ControlledStream(queue: queue), microphone = ControlledStream(queue: queue)
        self.system = system; self.microphone = microphone
        let events = events
        service = RecordingService(deadlineNanoseconds: deadlineNanoseconds, makeMeetingDriver: { id, paths, event in
            NativeMeetingCaptureDriver(microphoneID: id, paths: paths, queue: queue, stopGrace: stopGrace,
                makeStream: { source, _, sample, stopped in
                    if source == .microphone && microphoneLookupFails { throw CaptureFailure.start }
                    let stream = source == .system ? system : microphone
                    stream.install(sample: sample, stopped: stopped)
                    return stream
                }, event: { value in events.record(value); event(value) })
        }, makeDriver: { _, _, _ in fatalError("Dictation capture must not be used by meeting driver tests") })
        service.onSourceLost = { [weak self] in self?.lost.append($0) }
        service.onInterruption = { [weak self] in self?.interruptions += 1 }
    }

    func start() async throws {
        let starting = Task { try await service.startMeeting(microphoneID: "mic", paths: paths) }
        let deadline = Date().addingTimeInterval(2)
        while system.starts == 0 || microphone.starts == 0 {
            guard Date() < deadline else { throw CaptureFailure.timeout }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        system.completeStart(nil)
        microphone.completeStart(nil)
        try await starting.value
    }

    func settle() async {
        // Flush controlled source callbacks and nested driver-queue work.
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
            await Task.yield()
        }
    }
}

private final class MeetingDriverEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [CaptureCompletion] = []
    private var failureCount = 0
    var failedStarts: Int { lock.lock(); defer { lock.unlock() }; return failureCount }
    var completions: [CaptureCompletion] { lock.lock(); defer { lock.unlock() }; return values }
    func record(_ event: CaptureEvent) {
        lock.lock(); defer { lock.unlock() }
        if case .finished(let completion) = event { values.append(completion) }
        if case .failedToStart = event { failureCount += 1 }
    }
}

private final class ControlledStream: CaptureStreaming, @unchecked Sendable {
    private let queue: DispatchQueue
    private var startCallback: ((Error?) -> Void)?
    private var stopCallback: ((Error?) -> Void)?
    private var sampleCallback: CaptureSampleHandler?
    private var stoppedCallback: ((Error) -> Void)?
    private var startCount = 0
    private var stopCount = 0
    private var releaseCount = 0
    var starts: Int { queue.sync { startCount } }
    var stops: Int { queue.sync { stopCount } }
    var releases: Int { queue.sync { releaseCount } }
    init(queue: DispatchQueue) { self.queue = queue }
    func install(sample: @escaping CaptureSampleHandler, stopped: @escaping (Error) -> Void) {
        queue.sync { sampleCallback = sample; stoppedCallback = stopped }
    }
    // Production driver calls these on its queue.
    func start(completion: @escaping (Error?) -> Void) { startCount += 1; startCallback = completion }
    func stop(completion: @escaping (Error?) -> Void) { stopCount += 1; stopCallback = completion }
    func detachOutputs() { releaseCount += 1 }
    func completeStart(_ error: Error?) { queue.async { self.startCallback?(error) } }
    func completeStop(_ error: Error?) { queue.async { self.stopCallback?(error) } }
    func sample(_ sample: CMSampleBuffer, at time: Double) {
        let transferred = ImmutableSample(value: sample)
        queue.async { self.sampleCallback?(transferred.value, time) }
    }
    func confirmStopped() { queue.async { self.stoppedCallback?(CaptureFailure.start) } }
}

// Synthetic buffers are fully constructed before transfer, then only read on
// the driver's serial queue. CoreMedia has no imported Sendable conformance.
private struct ImmutableSample: @unchecked Sendable {
    let value: CMSampleBuffer
}

private final class LookupGate: @unchecked Sendable {
    private let lock = NSLock()
    private var waiter: CheckedContinuation<Void, Never>?
    private var wasEntered = false
    private var released = false
    var entered: Bool { lock.lock(); defer { lock.unlock() }; return wasEntered }
    func wait() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            wasEntered = true
            if released { lock.unlock(); continuation.resume() }
            else { waiter = continuation; lock.unlock() }
        }
    }
    func release() {
        lock.lock()
        released = true
        let continuation = waiter
        waiter = nil
        lock.unlock()
        continuation?.resume()
    }
}
