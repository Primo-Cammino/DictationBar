import AVFoundation
import Foundation

/// Samples, input configuration and file finalization share one serial queue.
/// Switching input never replaces the recording's persistent PCM writer.
final class NativeCaptureDriver: NSObject, CaptureDriving, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "DictationBar.capture")
    private var microphoneID: String
    private let paths: RecordingPaths
    private let event: (CaptureEvent) -> Void
    private var session: AVCaptureSession?
    private var input: AVCaptureDeviceInput?
    private var output: AVCaptureAudioDataOutput?
    private var writer: PCMRecordingWriter?
    private var observers: [NSObjectProtocol] = []
    private var interrupted = false
    private var started = false
    private var stopRequested = false
    private var finished = false

    init(microphoneID: String, paths: RecordingPaths, event: @escaping (CaptureEvent) -> Void) {
        self.microphoneID = microphoneID
        self.paths = paths
        self.event = event
    }

    func start() {
        queue.async { [self] in
            guard !started, !finished, !stopRequested else { return }
            do {
                let (session, input, output) = try Self.makeSession(microphoneID: microphoneID)
                let device = input.device
                self.session = session
                self.input = input
                self.output = output
                writer = try PCMRecordingWriter(paths: paths)
                output.setSampleBufferDelegate(self, queue: queue)
                observe(session)
                session.startRunning()
                guard session.isRunning, device.isConnected else { throw CaptureFailure.start }
                started = true
                event(.started)
            } catch {
                try? writer?.close()
                cleanup()
                finished = true
                event(.failedToStart)
            }
        }
    }

    func stop() {
        queue.async { [self] in
            guard !finished else { return }
            stopRequested = true
            finish()
        }
    }

    /// Input for one connected microphone, only with granted microphone access.
    private static func audioInput(id: String) throws -> AVCaptureDeviceInput {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
              let device = AVCaptureDevice(uniqueID: id), device.hasMediaType(.audio),
              device.isConnected else {
            throw CaptureFailure.deviceUnavailable
        }
        return try AVCaptureDeviceInput(device: device)
    }

    /// A configured, not yet running session for one connected, authorized microphone.
    static func makeSession(microphoneID: String) throws
        -> (AVCaptureSession, AVCaptureDeviceInput, AVCaptureAudioDataOutput) {
        let input = try audioInput(id: microphoneID)
        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        session.beginConfiguration()
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw CaptureFailure.configuration
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
        return (session, input, output)
    }

    func switchMicrophone(to id: String) {
        queue.async { [self] in
            guard started, !finished, !stopRequested, id != microphoneID,
                  let session, let original = input else { return }
            do {
                let replacement = try Self.audioInput(id: id)
                let device = replacement.device
                session.beginConfiguration()
                session.removeInput(original)
                if session.canAddInput(replacement), device.isConnected {
                    session.addInput(replacement)
                    session.commitConfiguration()
                    input = replacement
                    microphoneID = replacement.device.uniqueID
                    // Notifications posted during the transaction are handled
                    // afterward on this queue against the actual current input.
                    guard device.isConnected, session.isRunning else {
                        restore(original, removing: replacement, in: session)
                        return
                    }
                    event(.microphoneChanged(microphoneID))
                } else {
                    let restored = original.device.isConnected && session.canAddInput(original)
                    if restored { session.addInput(original) }
                    session.commitConfiguration()
                    event(.microphoneSwitchFailed)
                    if !restored || !original.device.isConnected || !session.isRunning {
                        interrupted = true
                        finish()
                    }
                }
            } catch {
                event(.microphoneSwitchFailed)
                if !original.device.isConnected || !session.isRunning {
                    interrupted = true
                    finish()
                }
            }
        }
    }

    private func restore(_ original: AVCaptureDeviceInput, removing replacement: AVCaptureDeviceInput,
                         in session: AVCaptureSession) {
        session.beginConfiguration()
        session.removeInput(replacement)
        let restored = original.device.isConnected && session.canAddInput(original)
        if restored { session.addInput(original) }
        session.commitConfiguration()
        input = restored ? original : nil
        microphoneID = original.device.uniqueID
        event(.microphoneSwitchFailed)
        if !restored || !original.device.isConnected || !session.isRunning {
            interrupted = true
            finish()
        }
    }

    private func observe(_ session: AVCaptureSession) {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { [weak self] _ in
            self?.interrupt()
        })
        observers.append(center.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: nil, queue: nil) { [weak self] note in
            guard let device = note.object as? AVCaptureDevice else { return }
            self?.queue.async { [weak self] in
                guard let self, self.input?.device.uniqueID == device.uniqueID,
                      self.input?.device.isConnected != true else { return }
                self.interruptOnQueue()
            }
        })
    }

    private func interrupt() {
        queue.async { [self] in
            interruptOnQueue()
        }
    }

    private func interruptOnQueue() {
        guard !finished else { return }
        interrupted = true
        finish()
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard started, !finished, !stopRequested else { return }
        do {
            guard let writer else { throw CaptureFailure.configuration }
            try writer.append(sampleBuffer)
        } catch {
            interruptOnQueue()
        }
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        output?.setSampleBufferDelegate(nil, queue: nil)
        session?.stopRunning()
        do { try writer?.close() } catch { interrupted = true }
        let result = CaptureCompletion(interrupted: interrupted)
        cleanup()
        event(.finished(result))
    }

    private func cleanup() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if session?.isRunning == true { session?.stopRunning() }
        writer = nil
        input = nil
        output = nil
        session = nil
    }
}

/// The meeting's microphone source. It never switches devices;
/// a disconnect or runtime error reports `stopped`, and the driver decides.
// start/stop/detachOutputs run on the driver's queue; samples arrive there too.
final class MicrophoneStream: NSObject, CaptureStreaming, AVCaptureAudioDataOutputSampleBufferDelegate,
                              @unchecked Sendable {
    private var session: AVCaptureSession?
    private let device: AVCaptureDevice
    private let output: AVCaptureAudioDataOutput
    private let sample: CaptureSampleHandler
    private var observers: [NSObjectProtocol] = []

    init(microphoneID: String, queue: DispatchQueue, sample: @escaping CaptureSampleHandler,
         stopped: @escaping (Error) -> Void) throws {
        let (session, input, output) = try NativeCaptureDriver.makeSession(microphoneID: microphoneID)
        self.session = session
        device = input.device
        self.output = output
        self.sample = sample
        super.init()
        output.setSampleBufferDelegate(self, queue: queue)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: nil) { _ in
            stopped(CaptureFailure.deviceUnavailable)
        })
        observers.append(center.addObserver(forName: .AVCaptureDeviceWasDisconnected, object: input.device,
                                            queue: nil) { _ in
            stopped(CaptureFailure.deviceUnavailable)
        })
    }

    func start(completion: @escaping (Error?) -> Void) {
        session?.startRunning()
        completion(session?.isRunning == true && device.isConnected ? nil : CaptureFailure.start)
    }

    func stop(completion: @escaping (Error?) -> Void) {
        output.setSampleBufferDelegate(nil, queue: nil)
        session?.stopRunning()
        completion(nil)
    }

    func detachOutputs() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        output.setSampleBufferDelegate(nil, queue: nil)
        if session?.isRunning == true { session?.stopRunning() }
        session = nil
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // A pure audio session may run on the device clock; the mixer needs host time.
        sample(sampleBuffer, sampleBuffer.hostSeconds(from: session?.synchronizationClock))
    }
}
