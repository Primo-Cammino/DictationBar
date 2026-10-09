import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

/// This seam controls only the ScreenCaptureKit boundary. The recording driver
/// still owns its real PCM writer and capture lifetime in both production/tests.
protocol BrowserCaptureStreaming: AnyObject, Sendable {
    func start(completion: @escaping (Error?) -> Void)
    func stop(completion: @escaping (Error?) -> Void)
    func detachOutputs()
}

// stream is installed before publication, then start/stop/detachOutputs run only
// on the driver's queue. Framework callbacks only forward immutable samples
// and errors to the driver; they never mutate adapter state.
final class ScreenCaptureBrowserStream: NSObject, BrowserCaptureStreaming, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private let sample: (CMSampleBuffer) -> Void
    private let stopped: (Error) -> Void

    private init(filter: SCContentFilter, configuration: SCStreamConfiguration, queue: DispatchQueue,
                 sample: @escaping (CMSampleBuffer) -> Void, stopped: @escaping (Error) -> Void) throws {
        self.sample = sample; self.stopped = stopped
        super.init()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
    }

    static func make(target: BrowserAudioTarget, queue: DispatchQueue,
                     sample: @escaping (CMSampleBuffer) -> Void,
                     stopped: @escaping (Error) -> Void) async throws -> any BrowserCaptureStreaming {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let app = content.applications.first(where: {
            $0.processID == target.processID && $0.bundleIdentifier == target.bundleID
        }), let display = content.displays.first else { throw CaptureFailure.deviceUnavailable }
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = 2; configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000; configuration.channelCount = 1
        return try ScreenCaptureBrowserStream(filter: filter, configuration: configuration, queue: queue,
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
        if type == .audio { sample(sampleBuffer) }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { stopped(error) }
}
