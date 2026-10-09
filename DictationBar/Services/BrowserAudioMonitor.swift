import AppKit
import CoreAudio
import Foundation

struct BrowserSuggestionPolicy {
    private var suppressed = Set<String>()
    mutating func update(_ outputs: [BrowserAudioTarget], enabled: Bool, busy: Bool) -> BrowserAudioTarget? {
        let active = Set(outputs.map(\.id))
        suppressed.formIntersection(active)
        if busy || !enabled { suppressed.formUnion(active); return nil }
        return outputs.filter { !suppressed.contains($0.id) }.min { $0.id < $1.id }
    }
    mutating func dismiss(_ target: BrowserAudioTarget) { suppressed.insert(target.id) }
}

@MainActor
protocol BrowserAudioMonitoring: AnyObject {
    var onOutputsChanged: (([BrowserAudioTarget]) -> Void)? { get set }
    var availabilityMessage: String? { get }
    func start()
    func stop()
    func requestCaptureAccess() async -> Bool
}

/// Monitoring reads output-stream activity metadata only. No tap, recording,
/// screen enumeration, permission request or network runs from construction.
@MainActor
final class NativeBrowserAudioMonitor: BrowserAudioMonitoring {
    var onOutputsChanged: (([BrowserAudioTarget]) -> Void)?
    private let queue = DispatchQueue(label: "DictationBar.browser-output-metadata")
    private var timer: DispatchSourceTimer?
    private var generation = UUID()
    private var lastOutputs: [BrowserAudioTarget]?
    var availabilityMessage: String? {
        if #available(macOS 14.2, *) { return nil }
        return "Browser-Audiohinweise benötigen macOS 14.2 oder neuer."
    }
    private static let browsers = Set(["com.apple.Safari", "com.google.Chrome", "org.mozilla.firefox", "com.microsoft.edgemac", "com.brave.Browser", "company.thebrowser.Browser", "com.operasoftware.Opera", "com.vivaldi.Vivaldi"])

    func start() {
        guard timer == nil else { return }
        guard #available(macOS 14.2, *) else { onOutputsChanged?([]); return }
        let token = UUID(); generation = token; lastOutputs = nil
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            let outputBundles = CoreAudioOutputActivity.bundleIDs()
            Task { @MainActor in
                guard let self, self.generation == token, self.timer != nil else { return }
                let targets = NSWorkspace.shared.runningApplications.compactMap { app -> BrowserAudioTarget? in
                    guard let bundle = app.bundleIdentifier, Self.browsers.contains(bundle),
                          outputBundles.contains(where: { $0 == bundle || $0.hasPrefix(bundle + ".") }) else { return nil }
                    return BrowserAudioTarget(bundleID: bundle, processID: app.processIdentifier, name: app.localizedName ?? "Browser")
                }
                let sorted = targets.sorted { $0.id < $1.id }
                guard sorted != self.lastOutputs else { return }
                self.lastOutputs = sorted
                self.onOutputsChanged?(sorted)
            }
        }
        self.timer = timer
        timer.resume()
    }

    func stop() { generation = UUID(); timer?.cancel(); timer = nil }
    func requestCaptureAccess() async -> Bool { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() }
}

@available(macOS 14.2, *)
private enum CoreAudioOutputActivity {
    static func bundleIDs() -> Set<String> {
        var list = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &list, 0, nil, &size) == noErr,
              size > 0, size <= 8192, size % UInt32(MemoryLayout<AudioObjectID>.size) == 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &list, 0, nil, &size, &objects) == noErr else { return [] }
        var result = Set<String>()
        for object in objects {
            var activity = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningOutput, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var running: UInt32 = 0; var activitySize = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(object, &activity, 0, nil, &activitySize, &running) == noErr, running != 0 else { continue }
            var identity = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var bundle: Unmanaged<CFString>?; var identitySize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            if AudioObjectGetPropertyData(object, &identity, 0, nil, &identitySize, &bundle) == noErr, let bundle {
                result.insert(bundle.takeRetainedValue() as String)
            }
        }
        return result
    }
}
