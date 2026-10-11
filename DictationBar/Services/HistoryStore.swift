import Darwin
import Foundation

struct HistorySnapshot {
    let entries: [HistoryEntry]
    let warnings: [String]
}

actor HistoryStore {
    let directory: URL
    private var operations: [UUID: OperationToken] = [:]
    private var writableOperations: [UUID: OperationToken] = [:]
    private let beforeWrite: () throws -> Void

    init(supportURL: URL = FolderStore.defaultSupportURL,
         beforeWrite: @escaping () throws -> Void = {}) {
        directory = supportURL.appendingPathComponent("records", isDirectory: true)
        self.beforeWrite = beforeWrite
    }

    func authorize(_ token: OperationToken) {
        operations[token.id] = token
        writableOperations[token.id] = nil
    }
    func authorizeExisting(_ token: OperationToken) throws {
        let entry = try JSONDecoder().decode(HistoryEntry.self, from: Data(contentsOf: recordURL(token.id)))
        try validate(entry)
        guard entry.id == token.id else { throw LocalStoreError.invalidRecord }
        operations[token.id] = token
        writableOperations[token.id] = token
    }
    func canWrite(_ token: OperationToken) -> Bool { writableOperations[token.id] == token }
    func revoke(_ token: OperationToken) {
        if operations[token.id] == token { operations[token.id] = nil; writableOperations[token.id] = nil }
    }

    func load() throws -> HistorySnapshot {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return HistorySnapshot(entries: [], warnings: [])
        }
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: [.isRegularFileKey]).filter { $0.pathExtension == "json" }
        var entries: [HistoryEntry] = []
        var warnings: [String] = []
        for url in urls {
            do {
                let entry = try JSONDecoder().decode(HistoryEntry.self, from: Data(contentsOf: url))
                try validate(entry)
                guard url.lastPathComponent == entry.id.uuidString + ".json" else {
                    throw LocalStoreError.invalidRecord
                }
                entries.append(entry)
            } catch {
                // Never include raw decoding errors: those may contain a transcript.
                warnings.append("Ein History-Eintrag konnte nicht gelesen werden. Das Original bleibt erhalten.")
            }
        }
        return HistorySnapshot(entries: entries.sorted { $0.createdAt > $1.createdAt }, warnings: warnings)
    }

    func create(_ entry: HistoryEntry, token: OperationToken) throws {
        try check(token, entry: entry)
        try beforeWrite()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entry)
        let temporary = directory.appendingPathComponent(".journal-\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .withoutOverwriting)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let destination = recordURL(entry.id)
        guard link(temporary.path, destination.path) == 0 else {
            if errno == EEXIST { throw LocalStoreError.collision }
            throw CocoaError(.fileWriteUnknown)
        }
        writableOperations[token.id] = token
    }

    func save(_ entry: HistoryEntry, token: OperationToken) throws {
        try check(token, entry: entry)
        guard writableOperations[entry.id] == token else { throw LocalStoreError.staleOperation }
        try writeExisting(entry)
    }

    /// Used only by local startup reconciliation before any operation starts.
    func saveRecovered(_ entry: HistoryEntry) throws {
        guard operations.isEmpty else { throw LocalStoreError.staleOperation }
        try validate(entry)
        try writeExisting(entry)
    }

    private func check(_ token: OperationToken, entry: HistoryEntry) throws {
        guard token.id == entry.id, operations[entry.id] == token else {
            throw LocalStoreError.staleOperation
        }
        try validate(entry)
    }

    private func writeExisting(_ entry: HistoryEntry) throws {
        guard FileManager.default.fileExists(atPath: recordURL(entry.id).path) else {
            throw LocalStoreError.invalidRecord
        }
        try beforeWrite()
        try JSONEncoder().encode(entry).write(to: recordURL(entry.id), options: .atomic)
    }

    private func recordURL(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    private func validate(_ entry: HistoryEntry) throws {
        guard entry.schemaVersion == 1, entry.createdAt.timeIntervalSince1970.isFinite,
              abs(entry.createdAt.timeIntervalSince1970) < Double(Int64.max) / 1_000 else {
            throw LocalStoreError.invalidRecord
        }
        let expected = HistoryEntry(id: entry.id, createdAt: entry.createdAt, microphoneID: entry.microphoneID,
                                   folderBookmark: entry.folderBookmark, kind: entry.kind)
        guard entry.filename == expected.filename, entry.stagingFilename == expected.stagingFilename else {
            throw LocalStoreError.invalidRecord
        }
    }
}
