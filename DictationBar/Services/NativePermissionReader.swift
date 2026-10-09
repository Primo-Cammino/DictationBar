import AVFoundation
import CoreGraphics

@MainActor
struct NativePermissionReader: PermissionReading {
    private let microphoneAuthorization: () -> Int
    private let screenCaptureAccess: () -> Bool

    init(microphoneAuthorization: @escaping () -> Int = {
        AVCaptureDevice.authorizationStatus(for: .audio).rawValue
    }, screenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }) {
        self.microphoneAuthorization = microphoneAuthorization
        self.screenCaptureAccess = screenCaptureAccess
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
            systemAudio: screenCaptureAccess() ? .authorized : .notVerified
        )
    }
}
