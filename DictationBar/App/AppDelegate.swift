import AppKit
import Observation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: DictationModel?
    private var waitingForTermination = false
    // Created here, not in the App's SceneBuilder (docs/solutions/build-errors/2026-10-09-scenebuilder-if-compiler-crash.md).
    private var statusPanel: StatusPanel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let model = Self.model {
            statusPanel = StatusPanel(model: model)
            followStatusPanel(model)
        }
        Task { await Self.model?.initialize() }
    }

    func applicationWillTerminate(_ notification: Notification) { statusPanel?.close() }

    /// Re-reads after every change of what the panel shows; content updates resize it.
    private func followStatusPanel(_ model: DictationModel) {
        let visible = withObservationTracking {
            model.panelActivity != nil || model.notice != nil || model.missingSource != nil
        } onChange: { [weak self, weak model] in
            Task { @MainActor in
                guard let model else { return }
                self?.followStatusPanel(model)
            }
        }
        statusPanel?.update(visible: visible)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model = Self.model else { return .terminateNow }
        guard !waitingForTermination else { return .terminateLater }
        waitingForTermination = true
        // Latch synchronously: no pending AX callback can post after Cmd-Q.
        model.requestQuit()
        Task {
            let mayQuit = await model.terminateSafely()
            waitingForTermination = false
            sender.reply(toApplicationShouldTerminate: mayQuit)
        }
        return .terminateLater
    }
}
