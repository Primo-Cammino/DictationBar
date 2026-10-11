import SwiftUI

@main
@MainActor
struct DictationBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: StatusModel
    @State private var dictation: DictationModel

    init() {
        let profile = RuntimeProfile.resolve(environment: ProcessInfo.processInfo.environment)
        let runtime = DictationRuntime.make(profile: profile)
        _dictation = State(initialValue: runtime)
        _model = State(initialValue: StatusModel(
            permissionReader: RuntimeFactory.make(profile: profile,
                production: { NativePermissionReader() as any PermissionReading },
                testing: { TestingPermissionReader() as any PermissionReading }),
            audioAvailabilityService: UnavailableAudioService()
        ))
        AppDelegate.model = runtime
    }

    var body: some Scene {
        // SceneBuilder only allows `if #available`, so the main window is unconditional.
        // ponytail: hosted tests also open it; harmless, suppress via AppDelegate if it gets in the way.
        WindowGroup("DictationBar", id: "main") {
            StatusView(model: model, dictation: dictation)
        }
        .windowResizability(.contentSize)
        .commands { DictationCommands() }

        MenuBarExtra {
            StatusView(model: model, dictation: dictation)
        } label: {
            Image(nsImage: BrandIcon.menuBar(recording: dictation.phase == .recording))
                .accessibilityLabel("DictationBar")
        }
        .menuBarExtraStyle(.window)

        Window("DictationBar – Einstellungen", id: "settings") {
            SettingsView(dictation: dictation, status: model)
        }
        .windowResizability(.contentSize)

        Window("DictationBar – History", id: "history") {
            HistoryView(dictation: dictation)
        }
        .defaultSize(width: 680, height: 520)
    }
}

/// The app's mark: a waveform in a rounded frame, drawn in code.
// ponytail: runtime Dock icon only; Finder shows the generic icon until an AppIcon asset catalog exists.
@MainActor
enum BrandIcon {
    /// Template image, so the menu bar tints it for light and dark mode.
    static func menuBar(recording: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 18), flipped: false) { rect in
            let frame = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 4.5, yRadius: 4.5)
            frame.lineWidth = 2
            NSColor.black.setStroke()
            frame.stroke()
            drawSymbol(recording ? "record.circle" : "waveform", pointSize: 10, color: .black, in: rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    static let app = NSImage(size: NSSize(width: 512, height: 512), flipped: false) { _ in
        // Body inset follows the macOS icon grid (824 of 1024).
        let body = NSRect(x: 50, y: 50, width: 412, height: 412)
        let shape = NSBezierPath(roundedRect: body, xRadius: 92, yRadius: 92)
        // Bright sky blue at the top to a clear mid blue at the bottom.
        NSGradient(starting: NSColor(srgbRed: 0.09, green: 0.47, blue: 0.96, alpha: 1),
                   ending: NSColor(srgbRed: 0.42, green: 0.80, blue: 1.0, alpha: 1))?.draw(in: shape, angle: 90)
        drawSymbol("waveform", pointSize: 200, color: .white, in: body)
        return true
    }

    private static func drawSymbol(_ name: String, pointSize: CGFloat, color: NSColor, in rect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config) else { return }
        // Center the glyph's own bounds; the image size carries uneven symbol padding.
        let glyph = symbol.alignmentRect
        symbol.draw(at: NSPoint(x: rect.midX - glyph.midX, y: rect.midY - glyph.midY),
                    from: .zero, operation: .sourceOver, fraction: 1)
    }
}

@MainActor
private struct DictationCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Einstellungen …") { show("settings") }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Button("DictationBar öffnen") { show("main") }
            Button("History …") { show("history") }
        }
    }

    private func show(_ id: String) {
        openWindow(id: id)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
private struct TestingPermissionReader: PermissionReading {
    func snapshot() -> PermissionSnapshot { PermissionSnapshot(microphone: .notDetermined, systemAudio: .notVerified) }
}
