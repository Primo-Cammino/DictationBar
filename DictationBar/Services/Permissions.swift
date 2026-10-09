enum MicrophonePermission: Equatable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case unknown

    var title: String {
        switch self {
        case .notDetermined: "Noch nicht angefragt"
        case .restricted: "Durch macOS eingeschränkt"
        case .denied: "Nicht erlaubt"
        case .authorized: "Erlaubt"
        case .unknown: "Unbekannt"
        }
    }
}

enum SystemAudioPermission: Equatable {
    case notVerified

    var title: String { "Noch nicht geprüft" }
}

struct PermissionSnapshot: Equatable {
    let microphone: MicrophonePermission
    let systemAudio: SystemAudioPermission
}

@MainActor
protocol PermissionReading {
    func snapshot() -> PermissionSnapshot
}
