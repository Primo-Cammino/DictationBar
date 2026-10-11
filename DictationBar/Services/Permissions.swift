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

/// Screen & System Audio Recording, requested when the first meeting starts.
enum SystemAudioPermission: Equatable {
    case notVerified, authorized

    var title: String { self == .authorized ? "Erlaubt" : "Noch nicht erlaubt" }
}

struct PermissionSnapshot: Equatable {
    let microphone: MicrophonePermission
    let systemAudio: SystemAudioPermission
}

@MainActor
protocol PermissionReading {
    func snapshot() -> PermissionSnapshot
}
