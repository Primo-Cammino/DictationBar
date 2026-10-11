import Foundation

enum OperationOrigin: String, Codable {
    case liveDictation
    case historyRetry
    case meeting
}

enum RecordingStopReason: String, Codable {
    case normal
    case interrupted
    case quit

    /// Quit beats a normal stop, which beats an interruption: a user stop is never an interruption.
    var priority: Int {
        switch self {
        case .interrupted: 0
        case .normal: 1
        case .quit: 2
        }
    }
}

struct OperationToken: Equatable {
    let id: UUID
    let generation: UInt64
    let origin: OperationOrigin
}

struct DictationSession: Equatable {
    let id: UUID
    let createdAt: Date
    let configuration: AppConfiguration
    let token: OperationToken
}

enum DictationPhase: Equatable {
    case idle
    case preparing
    case recording
    case saving
    case transcribing
    case persisting
    case inserting
    case failed

    var title: String {
        switch self {
        case .idle: "Bereit"
        case .preparing: "Aufnahme vorbereiten"
        case .recording: "Aufnahme läuft"
        case .saving: "Aufnahme speichern"
        case .transcribing: "Text transkribieren"
        case .persisting: "Text speichern"
        case .inserting: "Text einfügen"
        case .failed: "Fehler"
        }
    }
}
