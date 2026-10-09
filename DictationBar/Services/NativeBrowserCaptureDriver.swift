@preconcurrency import CoreMedia
import Foundation

/// One explicit browser recording. Audio callbacks and file ownership are
/// serialized; late content/start/stop callbacks cannot revive a finished driver.
// All mutable capture state is confined to queue; the async content lookup
// transfers the configured stream back to that queue. The stream factory
// delivers read-only samples on queue, preserving sample/stop ordering.
final class NativeBrowserCaptureDriver: CaptureDriving, @unchecked Sendable {
    typealias StreamFactory = (BrowserAudioTarget, DispatchQueue, @escaping (CMSampleBuffer) -> Void,
                               @escaping (Error) -> Void) async throws -> any BrowserCaptureStreaming
    private let queue: DispatchQueue
    private let makeStream: StreamFactory
    private let target: BrowserAudioTarget
    private let paths: RecordingPaths
    private let event: (CaptureEvent) -> Void
    private var stream: (any BrowserCaptureStreaming)?
    private var writer: PCMRecordingWriter?
    private var started = false
    private var stopRequested = false
    private var stopIssued = false
    private var interrupted = false
    private var finished = false

    init(target: BrowserAudioTarget, paths: RecordingPaths,
         queue: DispatchQueue = DispatchQueue(label: "DictationBar.browser-capture"),
         makeStream: @escaping StreamFactory = ScreenCaptureBrowserStream.make,
         event: @escaping (CaptureEvent) -> Void) {
        self.target = target; self.paths = paths; self.event = event
        self.queue = queue; self.makeStream = makeStream
    }

    func start() {
        Task { [self] in
            do {
                let stream = try await makeStream(target, queue,
                    { [self] sample in receive(sample) },
                    { [self] _ in queue.async { [self] in finish(interrupted: true, failedStart: !started) } })
                queue.async { [self] in configureStream(stream) }
            } catch { queue.async { [self] in finish(interrupted: true, failedStart: true) } }
        }
    }

    private func configureStream(_ stream: any BrowserCaptureStreaming) {
        guard !finished, !stopRequested else { stream.detachOutputs(); return }
        self.stream = stream
        do {
            writer = try PCMRecordingWriter(paths: paths)
            stream.start { [self] error in
                queue.async { [self] in captureStarted(error) }
            }
        } catch { finish(interrupted: true, failedStart: true) }
    }

    private func captureStarted(_ error: Error?) {
        guard !finished, !started else { return }
        if error != nil { finish(interrupted: true, failedStart: true); return }
        started = true
        event(.started)
        if stopRequested { stopStream() }
    }

    func stop() {
        queue.async { [self] in
            guard !finished else { return }
            stopRequested = true
            if started { stopStream() }
            else if stream == nil { finish(interrupted: true, failedStart: true) }
        }
    }

    private func stopStream() {
        guard started, !stopIssued, let stream else { return }
        stopIssued = true
        stream.stop { [self] error in
            queue.async { [self] in
                guard !finished else { return }
                if error != nil {
                    // ScreenCaptureKit reports a failed stop here. Keep the
                    // capture gate and writer until a delegate confirms stop.
                    interrupted = true
                } else { finish(interrupted: interrupted, failedStart: false) }
            }
        }
    }

    private func receive(_ sampleBuffer: CMSampleBuffer) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !finished, !interrupted else { return }
        do { try writer?.append(sampleBuffer) }
        catch {
            interrupted = true
            stopRequested = true
            // Audio can arrive before start acknowledgement. Wait for that
            // acknowledgement before issuing the one native stop request.
            stopStream()
        }
    }

    private func finish(interrupted: Bool, failedStart: Bool) {
        guard !finished else { return }
        finished = true
        var failed = interrupted
        do { try writer?.close() } catch { failed = true }
        writer = nil
        stream?.detachOutputs()
        stream = nil
        if failedStart { event(.failedToStart) }
        else { event(.finished(CaptureCompletion(interrupted: failed))) }
    }
}
