@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import XCTest
@testable import DictationBar

@MainActor
final class NativeBrowserCaptureDriverTests: XCTestCase {
    func testSampleFailureRetainsGateAndUnclosedWAVUntilConfirmedStop() async throws {
        let h = try await BrowserDriverHarness(); defer { h.fixture.cleanup() }
        try await h.start()
        h.stream.sample(try sample(value: 8_192))
        h.stream.sample(try invalidSample())
        try await wait { h.stream.stops == 1 }
        await h.settle()
        XCTAssertTrue(h.service.isActive, "A requested stop is not confirmed shutdown")
        XCTAssertEqual(h.completions.count, 0)
        let pending = try Data(contentsOf: h.paths.staging)
        XCTAssertGreaterThan(pending.count, 44)
        XCTAssertEqual(littleEndian32(pending, at: 40), 0, "The writer must remain open until shutdown")
        if h.service.isActive {
            do { try await h.service.startBrowser(h.target, paths: h.paths); XCTFail("Expected busy") }
            catch { guard case CaptureFailure.busy = error else { XCTFail("Expected busy, got \(error)"); return } }
        }
        h.stream.completeStop(nil)
        try await wait { !h.service.isActive }
        XCTAssertEqual(h.completions, [CaptureCompletion(interrupted: true)])
        XCTAssertGreaterThan(try WAVValidator.inspect(h.paths.staging).frames, 0)
        let saved = try Data(contentsOf: h.paths.staging)
        h.stream.sample(try sample(value: -8_192))
        h.stream.confirmStopped()
        h.stream.completeStop(nil)
        await h.settle()
        XCTAssertEqual(h.completions.count, 1)
        XCTAssertEqual(try Data(contentsOf: h.paths.staging), saved)
    }

    func testStopErrorKeepsGateUntilDelegateConfirmsShutdown() async throws {
        let h = try await BrowserDriverHarness(); defer { h.fixture.cleanup() }
        try await h.start()
        h.stream.sample(try sample(value: 8_192))
        let stopping = Task { try await h.service.stop() }
        try await wait { h.stream.stops == 1 }
        h.stream.completeStop(CaptureFailure.timeout)
        await h.settle()
        XCTAssertTrue(h.service.isActive, "stopCapture error denotes failed stop")
        XCTAssertEqual(h.completions.count, 0)
        h.stream.confirmStopped()
        let completion = try await stopping.value
        XCTAssertTrue(completion.interrupted)
        XCTAssertFalse(h.service.isActive)
        XCTAssertEqual(h.completions.count, 1)
    }

    func testRealSampleCallbackProducesExpectedPCMThenIgnoresLateAudio() async throws {
        let h = try await BrowserDriverHarness(); defer { h.fixture.cleanup() }
        try await h.start()
        h.stream.sample(try sample(value: 8_192))
        let stopping = Task { try await h.service.stop() }
        try await wait { h.stream.stops == 1 }
        h.stream.completeStop(nil)
        let completion = try await stopping.value
        XCTAssertFalse(completion.interrupted)
        let info = try WAVValidator.inspect(h.paths.staging)
        XCTAssertEqual(info.frames, 480)
        let file = try AVAudioFile(forReading: h.paths.staging)
        let pcm = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 480))
        try file.read(into: pcm)
        XCTAssertEqual(pcm.floatChannelData![0][240], 0.25, accuracy: 0.001)
        let saved = try Data(contentsOf: h.paths.staging)
        h.stream.sample(try sample(value: -8_192))
        await h.settle()
        XCTAssertEqual(try Data(contentsOf: h.paths.staging), saved)
    }

    func testStopDuringPendingStartWaitsForStartThenStopsExactlyOnce() async throws {
        let h = try await BrowserDriverHarness(); defer { h.fixture.cleanup() }
        let starting = Task { try await h.service.startBrowser(h.target, paths: h.paths) }
        try await wait { h.stream.starts == 1 }
        let first = Task { try await h.service.stop() }
        await h.settle()
        XCTAssertTrue(h.service.isActive)
        XCTAssertEqual(h.stream.stops, 0)
        h.stream.completeStart(nil)
        try await starting.value
        try await wait { h.stream.stops == 1 }
        let second = Task { try await h.service.stop() }
        await h.settle()
        XCTAssertEqual(h.stream.stops, 1)
        h.stream.completeStop(nil)
        _ = try await first.value
        _ = try await second.value
        h.stream.completeStart(nil)
        h.stream.confirmStopped()
        await h.settle()
        XCTAssertEqual(h.stream.stops, 1)
        XCTAssertEqual(h.completions.count, 1)
        XCTAssertFalse(h.service.isActive)
    }

    func testFailedStartClosesWriterAndLateSuccessCannotReviveCapture() async throws {
        let h = try await BrowserDriverHarness(); defer { h.fixture.cleanup() }
        let starting = Task { try await h.service.startBrowser(h.target, paths: h.paths) }
        try await wait { h.stream.starts == 1 }
        h.stream.completeStart(CaptureFailure.start)
        do { try await starting.value; XCTFail("Expected failed start") }
        catch { guard case CaptureFailure.start = error else { XCTFail("Expected start failure, got \(error)"); return } }
        XCTAssertFalse(h.service.isActive)
        XCTAssertEqual(try Data(contentsOf: h.paths.staging).count, 44)
        h.stream.completeStart(nil)
        await h.settle()
        XCTAssertFalse(h.service.isActive)
        XCTAssertEqual(h.stream.stops, 0)
    }

    func testWriterFailureBeforeStartAcknowledgementWaitsForConfirmedShutdown() async throws {
        let h = try await BrowserDriverHarness(); defer { h.fixture.cleanup() }
        let starting = Task { try await h.service.startBrowser(h.target, paths: h.paths) }
        try await wait { h.stream.starts == 1 }
        h.stream.sample(try sample(value: 8_192))
        h.stream.sample(try invalidSample())
        await h.settle()
        XCTAssertTrue(h.service.isActive)
        XCTAssertEqual(h.stream.stops, 0)
        XCTAssertEqual(h.completions.count, 0)
        h.stream.completeStart(nil)
        try await starting.value
        try await wait { h.stream.stops == 1 }
        XCTAssertTrue(h.service.isActive)
        XCTAssertEqual(littleEndian32(try Data(contentsOf: h.paths.staging), at: 40), 0)
        h.stream.completeStop(nil)
        try await wait { !h.service.isActive }
        XCTAssertEqual(h.completions, [CaptureCompletion(interrupted: true)])
        XCTAssertGreaterThan(try WAVValidator.inspect(h.paths.staging).frames, 0)
    }

    func testDirectRepeatedStopsRequestNativeStopOnce() async throws {
        let h = try await BrowserDriverHarness(); defer { h.fixture.cleanup() }
        let events = BrowserDriverEvents()
        let stream = h.stream
        let driver = NativeBrowserCaptureDriver(target: h.target, paths: h.paths, queue: h.queue,
            makeStream: { _, _, sample, stopped in stream.install(sample: sample, stopped: stopped); return stream },
            event: events.record)
        driver.start()
        try await wait { stream.starts == 1 }
        stream.completeStart(nil)
        await h.settle()
        driver.stop(); driver.stop(); driver.stop()
        try await wait { stream.stops == 1 }
        await h.settle()
        XCTAssertEqual(stream.stops, 1)
        XCTAssertEqual(events.completions.count, 0)
        stream.completeStop(nil)
        await h.settle()
        XCTAssertEqual(events.completions.count, 1)
    }

    func testStopBeforeContentLookupCannotStartLateStreamOrReleaseReservation() async throws {
        let h = try await BrowserDriverHarness(); defer { h.fixture.cleanup() }
        let events = BrowserDriverEvents()
        let gate = BrowserLookupGate()
        let stream = h.stream
        let driver = NativeBrowserCaptureDriver(target: h.target, paths: h.paths, queue: h.queue,
            makeStream: { _, _, sample, stopped in
                stream.install(sample: sample, stopped: stopped)
                await gate.wait()
                return stream
            }, event: events.record)
        driver.start()
        try await wait { gate.entered }
        driver.stop()
        await h.settle()
        XCTAssertEqual(events.failedStarts, 1)
        gate.release()
        try await wait { stream.releases == 1 }
        await h.settle()
        XCTAssertEqual(stream.starts, 0)
        XCTAssertEqual(stream.stops, 0)
        XCTAssertEqual(events.failedStarts, 1)
        XCTAssertEqual(try Data(contentsOf: h.paths.staging).count, 0)
    }

    private func wait(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() {
            guard Date() < deadline else { XCTFail("Timed out waiting for driver callback"); throw CaptureFailure.timeout }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
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

    private func littleEndian32(_ data: Data, at offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
    }
}

@MainActor
private final class BrowserDriverHarness {
    let fixture: LocalStoreFixture
    let paths: RecordingPaths
    let target = BrowserAudioTarget(bundleID: "test.browser", processID: 123, name: "Local test browser")
    let queue = DispatchQueue(label: "DictationBarTests.browser-driver")
    let stream: ControlledBrowserStream
    let service: RecordingService
    private let events = BrowserDriverEvents()
    var completions: [CaptureCompletion] { events.completions }

    init() async throws {
        fixture = try LocalStoreFixture()
        let entry = try fixture.entry()
        paths = try await RecordingStore(history: HistoryStore(supportURL: fixture.support))
            .prepare(entry, token: fixture.token(entry))
        let queue = queue
        let stream = ControlledBrowserStream(queue: queue)
        self.stream = stream
        let events = events
        service = RecordingService(makeBrowserDriver: { target, paths, event in
            NativeBrowserCaptureDriver(target: target, paths: paths, queue: queue,
                makeStream: { _, _, sample, stopped in
                    stream.install(sample: sample, stopped: stopped)
                    return stream
                }, event: { value in events.record(value); event(value) })
        }, makeDriver: { _, _, _ in fatalError("Microphone must not be used by browser driver tests") })
    }

    func start() async throws {
        let starting = Task { try await service.startBrowser(target, paths: paths) }
        let deadline = Date().addingTimeInterval(2)
        while stream.starts == 0 {
            guard Date() < deadline else { throw CaptureFailure.timeout }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        stream.completeStart(nil)
        try await starting.value
    }

    func settle() async {
        // Flush controlled source callbacks and nested driver-queue work.
        // Tests await service completion separately when it is required.
        for _ in 0..<3 {
            await withCheckedContinuation { continuation in queue.async { continuation.resume() } }
            await Task.yield()
        }
    }
}

private final class BrowserDriverEvents: @unchecked Sendable {
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

private final class ControlledBrowserStream: BrowserCaptureStreaming, @unchecked Sendable {
    private let queue: DispatchQueue
    private var startCallback: ((Error?) -> Void)?
    private var stopCallback: ((Error?) -> Void)?
    private var sampleCallback: ((CMSampleBuffer) -> Void)?
    private var stoppedCallback: ((Error) -> Void)?
    private var startCount = 0
    private var stopCount = 0
    private var releaseCount = 0
    var starts: Int { queue.sync { startCount } }
    var stops: Int { queue.sync { stopCount } }
    var releases: Int { queue.sync { releaseCount } }
    init(queue: DispatchQueue) { self.queue = queue }
    func install(sample: @escaping (CMSampleBuffer) -> Void, stopped: @escaping (Error) -> Void) {
        queue.sync { sampleCallback = sample; stoppedCallback = stopped }
    }
    // Production driver calls these on its queue.
    func start(completion: @escaping (Error?) -> Void) { startCount += 1; startCallback = completion }
    func stop(completion: @escaping (Error?) -> Void) { stopCount += 1; stopCallback = completion }
    func detachOutputs() { releaseCount += 1 }
    func completeStart(_ error: Error?) { queue.async { self.startCallback?(error) } }
    func completeStop(_ error: Error?) { queue.async { self.stopCallback?(error) } }
    func sample(_ sample: CMSampleBuffer) {
        let transferred = ImmutableBrowserSample(value: sample)
        queue.async { self.sampleCallback?(transferred.value) }
    }
    func confirmStopped() { queue.async { self.stoppedCallback?(CaptureFailure.start) } }
}

// Synthetic buffers are fully constructed before transfer, then only read on
// the driver's serial queue. CoreMedia has no imported Sendable conformance.
private struct ImmutableBrowserSample: @unchecked Sendable {
    let value: CMSampleBuffer
}

private final class BrowserLookupGate: @unchecked Sendable {
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
