import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: DictationModel?
    private var waitingForTermination = false
    private let browserToast = BrowserRecordingToast()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let model = Self.model {
            model.onBrowserSuggestionChanged = { [weak self, weak model] target in
                guard let model else { return }
                self?.browserToast.show(target, model: model)
            }
        }
        Task { await Self.model?.initialize() }
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
