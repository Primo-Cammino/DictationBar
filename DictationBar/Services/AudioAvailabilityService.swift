enum RecordingAvailability: Equatable {
    case notImplemented

    var isAvailable: Bool { false }
    var title: String { "Noch nicht verfügbar" }
}

@MainActor
protocol AudioAvailabilityProviding {
    var availability: RecordingAvailability { get }
}

@MainActor
struct UnavailableAudioService: AudioAvailabilityProviding {
    var availability: RecordingAvailability { .notImplemented }
}
