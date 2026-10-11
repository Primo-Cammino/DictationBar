import AppKit
import SwiftUI

/// What runs right now, as shown by the floating status panel.
enum PanelActivity: Equatable {
    case dictation, transcription, meetingStarting, meetingSaving
    case meeting(since: Date)
}

/// A short panel message. Its kind decides how long it stays.
struct PanelNotice: Equatable {
    enum Kind: Equatable { case info, saved, interrupted, error, permission }
    let id = UUID()
    let kind: Kind
    let text: String
    var entry: HistoryEntry?

    var seconds: Double {
        switch kind {
        case .info: 3
        case .saved: 6
        case .error: 8
        case .permission: 10
        case .interrupted: 15
        }
    }

    /// System Settings › Privacy & Security › Screen & System Audio Recording.
    static let systemAudioSettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
}

enum StatusPanelPlacement {
    static let margin: CGFloat = 16

    /// The user's last position while it is still on a connected display,
    /// otherwise bottom right of the display under the mouse, clear of the
    /// centred Zoom and Teams controls.
    static func origin(size: NSSize, saved: NSPoint?, visibleFrames: [NSRect], mouseScreen: NSRect) -> NSPoint {
        if let saved, visibleFrames.contains(where: {
            $0.contains(NSPoint(x: saved.x + size.width / 2, y: saved.y + size.height / 2))
        }) { return saved }
        return NSPoint(x: mouseScreen.maxX - size.width - margin, y: mouseScreen.minY + margin)
    }
}

/// Borderless, non-activating panel above full-screen apps and on every Space.
/// It never takes focus, reacts to the first click and can be dragged away.
@MainActor
final class StatusPanel {
    private let panel: NSPanel
    private let host: NSHostingView<StatusPanelView>
    private var saved: NSPoint?
    private var placing = false

    init(model: DictationModel) {
        host = FirstClickHostingView(rootView: StatusPanelView(model: model))
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 60),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        // ponytail: .screenSaver per Apple DTS to float over other apps' full screen; try .statusBar if Mission Control suffers.
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = host
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.placing else { return }
                self.saved = self.panel.frame.origin
            }
        }
    }

    func update(visible: Bool) {
        guard visible else { panel.orderOut(nil); return }
        let size = host.fittingSize
        placing = true
        if panel.isVisible {
            // Keep the bottom-left corner, so content grows upwards.
            panel.setFrame(NSRect(origin: panel.frame.origin, size: size), display: true)
        } else {
            let mouse = NSEvent.mouseLocation
            let screens = NSScreen.screens
            let mouseScreen = screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? screens[0]
            let origin = StatusPanelPlacement.origin(size: size, saved: saved, visibleFrames: screens.map(\.visibleFrame),
                                                     mouseScreen: mouseScreen.visibleFrame)
            panel.setFrame(NSRect(origin: origin, size: size), display: true)
            panel.orderFrontRegardless()
        }
        placing = false
    }

    func close() { panel.close() }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
struct StatusPanelView: View {
    let model: DictationModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let source = model.missingSource {
                Label(source == .microphone ? "Mikrofon fehlt – es wird nur der Systemton aufgenommen."
                                            : "Systemton fehlt – es wird nur das Mikrofon aufgenommen.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout.weight(.semibold))
            }
            if let activity = model.panelActivity { activityRow(activity) }
            if let notice = model.notice { noticeRow(notice) }
        }
        .padding(12)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder private func activityRow(_ activity: PanelActivity) -> some View {
        switch activity {
        case .dictation:
            Label("Diktat läuft", systemImage: "mic.fill").foregroundStyle(.red)
        case .transcription: busy("Transkription …")
        case .meetingStarting: busy("Meeting startet …")
        case .meetingSaving: busy("Meeting wird gespeichert …")
        case .meeting(let since):
            HStack(spacing: 8) {
                Image(systemName: "record.circle").foregroundStyle(.red)
                Text("Meeting")
                Text(since, style: .timer).monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                Button("Stopp") { model.toggleMeeting() }.buttonStyle(.borderedProminent).tint(.red)
            }
        }
    }

    private func busy(_ text: String) -> some View {
        HStack(spacing: 8) { ProgressView().controlSize(.small); Text(text) }
    }

    @ViewBuilder private func noticeRow(_ notice: PanelNotice) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(notice.text).fixedSize(horizontal: false, vertical: true)
            } icon: {
                switch notice.kind {
                case .saved: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .interrupted, .error, .permission: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .info: Image(systemName: "info.circle").foregroundStyle(.secondary)
                }
            }
            if let entry = notice.entry {
                HStack {
                    if let duration = entry.duration {
                        Text(Duration.seconds(duration).formatted(.time(pattern: .hourMinuteSecond)))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Im Finder zeigen", action: entry.revealInFinder)
                }
            }
            if notice.kind == .permission {
                Button("Systemeinstellungen öffnen") { NSWorkspace.shared.open(PanelNotice.systemAudioSettings) }
            }
        }
    }
}
