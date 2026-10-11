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
    /// Missing in dictations and in journals written before meetings existed.
    enum Kind: String, Codable { case meeting }

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
    let kind: Kind?
    var duration: TimeInterval?
    var status: HistoryStatus = .preparing
    var transcript: String?
    var insertion: InsertionStatus = .notAttempted
    var message: String?

    var isMeeting: Bool { kind == .meeting }
    /// Meetings are uploaded elsewhere, so transcription hints stay hidden; a failure still explains itself.
    var visibleMessage: String? { isMeeting && status != .failed ? nil : message }

    init(id: UUID, createdAt: Date, microphoneID: String, folderBookmark: Data, kind: Kind? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.microphoneID = microphoneID
        self.folderBookmark = folderBookmark
        self.kind = kind
        let stamp = Int(createdAt.timeIntervalSince1970 * 1_000)
        let prefix = kind == .meeting ? "Meeting" : "Dictation"
        filename = "\(prefix)-\(stamp)-\(id.uuidString).wav"
        stagingFilename = ".\(prefix)-\(stamp)-\(id.uuidString).recording.wav"
    }
}
