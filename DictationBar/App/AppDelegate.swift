import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: DictationModel?
    private var waitingForTermination = false

    func applicationDidFinishLaunching(_ notification: Notification) {
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
