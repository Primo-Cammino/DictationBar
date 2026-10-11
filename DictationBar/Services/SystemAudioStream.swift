import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

/// This seam controls only the native capture boundary of one meeting source.
/// The meeting driver still owns its real mixer, PCM writer and capture lifetime.
/// `sample` delivers each buffer with its presentation time on the host clock.
protocol CaptureStreaming: AnyObject, Sendable {
    func start(completion: @escaping (Error?) -> Void)
    func stop(completion: @escaping (Error?) -> Void)
    func detachOutputs()
}

typealias CaptureSampleHandler = (CMSampleBuffer, Double) -> Void

// stream is installed before publication, then start/stop/detachOutputs run only
// on the driver's queue. Framework callbacks only forward immutable samples
// and errors to the driver; they never mutate adapter state.
final class SystemAudioStream: NSObject, CaptureStreaming, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private let sample: CaptureSampleHandler
    private let stopped: (Error) -> Void

    private init(filter: SCContentFilter, configuration: SCStreamConfiguration, queue: DispatchQueue,
                 sample: @escaping CaptureSampleHandler, stopped: @escaping (Error) -> Void) throws {
        self.sample = sample; self.stopped = stopped
        super.init()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
    }

    /// Audio of every app on the main display except DictationBar itself.
    static func make(queue: DispatchQueue, sample: @escaping CaptureSampleHandler,
                     stopped: @escaping (Error) -> Void) async throws -> any CaptureStreaming {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
        else { throw CaptureFailure.deviceUnavailable }
        let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2; configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000; configuration.channelCount = 1
        return try SystemAudioStream(filter: filter, configuration: configuration, queue: queue,
                                     sample: sample, stopped: stopped)
    }

    func start(completion: @escaping (Error?) -> Void) { stream?.startCapture(completionHandler: completion) }
    func stop(completion: @escaping (Error?) -> Void) { stream?.stopCapture(completionHandler: completion) }
    func detachOutputs() {
        // Break output/delegate ownership only after confirmed shutdown (or
        // before start), including late content results that were cancelled.
        try? stream?.removeStreamOutput(self, type: .audio)
        stream = nil
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        let host = CMSyncConvertTime(sampleBuffer.presentationTimeStamp,
                                     from: stream.synchronizationClock ?? CMClockGetHostTimeClock(),
                                     to: CMClockGetHostTimeClock())
        sample(sampleBuffer, host.seconds)
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { stopped(error) }
}
