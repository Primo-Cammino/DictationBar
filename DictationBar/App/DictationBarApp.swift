import SwiftUI

@main
@MainActor
struct DictationBarApp: App {
    @State private var model = StatusModel(
        permissionReader: NativePermissionReader(),
        audioAvailabilityService: UnavailableAudioService()
    )

    var body: some Scene {
        MenuBarExtra("DictationBar", systemImage: "waveform") {
            StatusView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
