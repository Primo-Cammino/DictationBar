@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation

/// One meeting recording: system audio and microphone, mixed into one WAV.
/// Start succeeds for both sources or for neither. Losing one
/// source keeps the recording going; losing both or a write error ends it as
/// interrupted. Late start/stop/sample callbacks cannot revive a finished driver.
// All mutable state is confined to queue. Stream factories run off-queue and
// hand their streams back to it; streams deliver samples on queue.
final class NativeMeetingCaptureDriver: CaptureDriving, @unchecked Sendable {
    typealias Source = MeetingMixer.Source
    typealias StreamFactory = (Source, DispatchQueue, @escaping CaptureSampleHandler,
                               @escaping (Error) -> Void) async throws -> any CaptureStreaming
    private enum State { case starting, running, stopping, ended }
    private static let sources = Source.allCases

    private let queue: DispatchQueue
    private let makeStream: StreamFactory
    private let paths: RecordingPaths
    private let stopGrace: DispatchTimeInterval
    private let event: (CaptureEvent) -> Void
    private var streams: [Source: any CaptureStreaming] = [:]
    private var states: [Source: State] = [:]
    private var writer: PCMRecordingWriter?
    private var mixer: MeetingMixer?
    private var started = false
    private var stopIssued = false
    private var interrupted = false
    private var finished = false

    /// `stopGrace` bounds how long a stop waits for a source that never confirms.
    init(microphoneID: String, paths: RecordingPaths,
         queue: DispatchQueue = DispatchQueue(label: "DictationBar.meeting-capture"),
         stopGrace: DispatchTimeInterval = .seconds(5),
         makeStream: StreamFactory? = nil,
         event: @escaping (CaptureEvent) -> Void) {
        self.paths = paths; self.queue = queue; self.stopGrace = stopGrace; self.event = event
        self.makeStream = makeStream ?? { source, queue, sample, stopped in
            switch source {
            case .system: try await SystemAudioStream.make(queue: queue, sample: sample, stopped: stopped)
            case .microphone: try MicrophoneStream(microphoneID: microphoneID, queue: queue, sample: sample, stopped: stopped)
            }
        }
    }

    func start() {
        Task { [self] in
            var created: [Source: any CaptureStreaming] = [:]
            do {
                for source in Self.sources {
                    created[source] = try await makeStream(source, queue,
                        { [self] sample, time in receive(sample, at: time, from: source) },
                        { [self] _ in queue.async { [self] in sourceEnded(source) } })
                }
                let streams = created
                queue.async { [self] in configure(streams) }
            } catch {
                let streams = created
                queue.async { [self] in
                    streams.values.forEach { $0.detachOutputs() }
                    finish(failedStart: true)
                }
            }
        }
    }

    func stop() {
        queue.async { [self] in
            guard !finished else { return }
            if started { stopAll() } else { interrupted = true; finish(failedStart: true) }
        }
    }

    private func configure(_ created: [Source: any CaptureStreaming]) {
        guard !finished else { created.values.forEach { $0.detachOutputs() }; return }
        streams = created
        do { writer = try PCMRecordingWriter(paths: paths) }
        catch { finish(failedStart: true); return }
        for (source, stream) in created {
            states[source] = .starting
            stream.start { [self] error in queue.async { [self] in startCompleted(source, stream, error) } }
        }
    }

    private func startCompleted(_ source: Source, _ stream: any CaptureStreaming, _ error: Error?) {
        guard !finished else {
            // The meeting already ended; never leave a late-starting capture running.
            streams[source] = nil
            if error == nil { stopAndDetach(stream) } else { stream.detachOutputs() }
            return
        }
        guard error == nil else { states[source] = .ended; finish(failedStart: true); return }
        states[source] = .running
        guard Self.sources.allSatisfy({ states[$0] == .running }) else { return }
        started = true
        event(.started)
    }

    private func stopAll() {
        guard !stopIssued else { return }
        stopIssued = true
        for source in Self.sources where states[source] == .running {
            states[source] = .stopping
            streams[source]?.stop { [self] error in queue.async { [self] in stopCompleted(source, error) } }
        }
        guard states.values.contains(.stopping) else { finish(failedStart: false); return }
        // The first confirmed source closes the file; a source that never
        // confirms cannot hold the recording gate beyond this grace period.
        queue.asyncAfter(deadline: .now() + stopGrace) { [self] in finish(failedStart: false) }
    }

    private func stopCompleted(_ source: Source, _ error: Error?) {
        guard !finished else { streams.removeValue(forKey: source)?.detachOutputs(); return }
        // A failed native stop is no confirmation; the other source or the grace period ends the file.
        guard error == nil else { return }
        states[source] = .ended
        finish(failedStart: false)
    }

    /// The native source stopped on its own: device gone, stream error or confirmed stop.
    private func sourceEnded(_ source: Source) {
        guard !finished else { return }
        switch states[source] {
        case .stopping?:
            stopCompleted(source, nil)
        case .running? where started:
            states[source] = .ended
            streams.removeValue(forKey: source)?.detachOutputs()
            if Self.sources.allSatisfy({ states[$0] == .ended }) {
                interrupted = true
                finish(failedStart: false)
            } else {
                event(.sourceLost(source))
            }
        case .starting?, .running?:
            states[source] = .ended
            finish(failedStart: true)
        case .ended?, nil:
            break
        }
    }

    private func receive(_ sampleBuffer: CMSampleBuffer, at hostTime: Double, from source: Source) {
        dispatchPrecondition(condition: .onQueue(queue))
        // Audio can arrive before the start acknowledgement.
        guard !finished, states[source] == .starting || states[source] == .running, let writer else { return }
        do {
            guard let buffer = try PCMRecordingWriter.pcmBuffer(sampleBuffer) else { return }
            let mixer = self.mixer ?? MeetingMixer(startHostTime: hostTime)
            self.mixer = mixer
            try mixer.append(buffer, hostTime: hostTime, source: source)
            if let mixed = mixer.mix(upTo: CMClockGetTime(CMClockGetHostTimeClock()).seconds) {
                try writer.append(mixed)
            }
        } catch {
            interrupted = true
            if started { stopAll() } else { finish(failedStart: true) }
        }
    }

    private func finish(failedStart: Bool) {
        guard !finished else { return }
        finished = true
        var failed = interrupted
        if !failedStart, let mixed = mixer?.finish() {
            do { try writer?.append(mixed) } catch { failed = true }
        }
        do { try writer?.close() } catch { failed = true }
        writer = nil
        mixer = nil
        for source in Self.sources { release(source) }
        if failedStart { event(.failedToStart) }
        else { event(.finished(CaptureCompletion(interrupted: failed))) }
    }

    private func stopAndDetach(_ stream: any CaptureStreaming) {
        stream.stop { [queue] _ in queue.async { stream.detachOutputs() } }
    }

    private func release(_ source: Source) {
        guard let stream = streams[source] else { return }
        switch states[source] {
        case .starting?, .stopping?:
            return // Their pending completions stop and detach the stream.
        case .running?:
            states[source] = .stopping
            stopAndDetach(stream)
            streams[source] = nil
        case .ended?, nil:
            streams[source] = nil
            stream.detachOutputs()
        }
    }
}
