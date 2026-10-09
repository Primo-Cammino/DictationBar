import AppKit
import SwiftUI

@MainActor
final class BrowserRecordingToast {
    private var panel: NSPanel?

    func show(_ target: BrowserAudioTarget?, model: DictationModel) {
        panel?.close()
        panel = nil
        guard let target, let screen = NSScreen.main else { return }
        let view = BrowserPrompt(target: target, record: { model.recordSuggestedBrowser(target) },
                                 dismiss: { model.dismissBrowserSuggestion() })
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 460, height: 112),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: view)
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.maxX - 480, y: screen.visibleFrame.maxY - 132))
        self.panel = panel
        panel.orderFrontRegardless()
    }
}

@MainActor
private struct BrowserPrompt: View {
    let target: BrowserAudioTarget
    let record: () -> Void
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "waveform").font(.title).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 5) {
                Text("Audio in \(target.name)").font(.headline)
                Text("Browser-Audio aufnehmen?").font(.callout)
            }
            Spacer()
            Button("Aufnehmen", action: record).buttonStyle(.borderedProminent)
            Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
                .help("Für diese Audio-Wiedergabe schließen")
        }
        .padding(20)
        .frame(width: 460, height: 112)
    }
}
