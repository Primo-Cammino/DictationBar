import AVFoundation

@MainActor
struct NativePermissionReader: PermissionReading {
    private let microphoneAuthorization: () -> Int

    init(microphoneAuthorization: @escaping () -> Int = {
        AVCaptureDevice.authorizationStatus(for: .audio).rawValue
    }) {
        self.microphoneAuthorization = microphoneAuthorization
    }

    func snapshot() -> PermissionSnapshot {
        let microphone: MicrophonePermission

        switch microphoneAuthorization() {
        case AVAuthorizationStatus.notDetermined.rawValue:
            microphone = .notDetermined
        case AVAuthorizationStatus.restricted.rawValue:
            microphone = .restricted
        case AVAuthorizationStatus.denied.rawValue:
            microphone = .denied
        case AVAuthorizationStatus.authorized.rawValue:
            microphone = .authorized
        default:
            microphone = .unknown
        }

        return PermissionSnapshot(
            microphone: microphone,
            systemAudio: .notVerified
        )
    }
}
