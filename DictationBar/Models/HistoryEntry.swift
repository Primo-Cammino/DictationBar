import Foundation

enum HistoryStatus: String, Codable {
    case preparing, recording, pending, transcribing, complete, interrupted, failed

    var title: String {
        switch self {
        case .preparing: "Aufnahme vorbereitet"
        case .recording: "Aufnahme läuft"
        case .pending: "Transkript ausstehend"
        case .transcribing: "Transkription ausstehend"
        case .complete: "Transkribiert"
        case .interrupted: "Unterbrochen – erneut transkribierbar"
        case .failed: "Fehler"
        }
    }
}

enum InsertionStatus: String, Codable {
    case notAttempted, confirmed, unconfirmed, unavailable, historyOnly

    var title: String {
        switch self {
        case .notAttempted: "Noch nicht eingefügt"
        case .confirmed: "Eingefügt"
        case .unconfirmed: "Einfügen nicht bestätigt – Text kopierbar"
        case .unavailable: "Kein geeignetes Ziel – Text kopierbar"
        case .historyOnly: "Text zum Kopieren bereit"
        }
    }
}

struct HistoryEntry: Codable, Equatable, Identifiable {
    var schemaVersion = 1
    let id: UUID
    let createdAt: Date
    let microphoneID: String
    var folderBookmark: Data
    let stagingFilename: String
    let filename: String
    /// Only a durable successful staging reservation permits startup salvage.
    /// Missing markers in earlier journals are treated conservatively.
    var stagingOwned: Bool? = false
    var sourceLabel: String?
    var duration: TimeInterval?
    var status: HistoryStatus = .preparing
    var transcript: String?
    var insertion: InsertionStatus = .notAttempted
    var message: String?

    init(id: UUID, createdAt: Date, microphoneID: String, folderBookmark: Data) {
        self.id = id
        self.createdAt = createdAt
        self.microphoneID = microphoneID
        self.folderBookmark = folderBookmark
        let stamp = Int(createdAt.timeIntervalSince1970 * 1_000)
        filename = "Dictation-\(stamp)-\(id.uuidString).wav"
        stagingFilename = ".Dictation-\(stamp)-\(id.uuidString).recording.wav"
    }
}
