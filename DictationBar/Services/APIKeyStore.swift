import Foundation

enum APIKeyFailure: LocalizedError, Equatable {
    case missing, locked, invalid, storage

    var errorDescription: String? {
        switch self {
        case .missing: "Bitte deinen Mistral-API-Key in den Einstellungen speichern."
        case .locked: "Der Schlüsselbund ist gesperrt oder der Zugriff wurde verweigert."
        case .invalid: "Bitte einen nicht leeren Mistral-API-Key eingeben."
        case .storage: "Der Mistral-Key konnte nicht gelesen oder gespeichert werden."
        }
    }
}

protocol APIKeyStoring {
    func hasKey() async throws -> Bool
    func read() async throws -> String
    func save(_ key: String) async throws
    func remove() async throws
}

/// Personal local app: the key lives in a user-only file instead of the Keychain,
/// so rebuilds never trigger a Keychain password prompt.
actor FileKeyStore: APIKeyStoring {
    private let url: URL

    init(supportURL: URL = FolderStore.defaultSupportURL) {
        url = supportURL.appendingPathComponent("mistral-api-key")
    }

    func hasKey() -> Bool { FileManager.default.fileExists(atPath: url.path) }

    func read() throws -> String {
        guard hasKey() else { throw APIKeyFailure.missing }
        guard let data = try? Data(contentsOf: url),
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { throw APIKeyFailure.storage }
        return key
    }

    func save(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw APIKeyFailure.invalid }
        let directory = url.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try Data(value.utf8).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { throw APIKeyFailure.storage }
    }

    func remove() throws {
        guard hasKey() else { return }
        do { try FileManager.default.removeItem(at: url) } catch { throw APIKeyFailure.storage }
    }
}
