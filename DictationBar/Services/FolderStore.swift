import Foundation

enum LocalStoreError: LocalizedError, Equatable {
    case missingFolder, invalidFolder, collision, invalidRecord, staleOperation, invalidWAV

    var errorDescription: String? {
        switch self {
        case .missingFolder: "Bitte einen Aufnahmeordner wählen."
        case .invalidFolder: "Der Aufnahmeordner ist nicht erreichbar. Bitte bewusst erneut auswählen."
        case .collision: "Eine Datei mit diesem Namen existiert bereits. Keine Datei wurde ersetzt."
        case .invalidRecord: "Ein History-Eintrag ist beschädigt oder hat eine unbekannte Version."
        case .staleOperation: "Der Vorgang ist nicht mehr aktuell."
        case .invalidWAV: "Die Aufnahme ist keine lesbare PCM-WAV mit Audio (48 kHz, mono, 16 Bit)."
        }
    }
}

struct ResolvedFolder {
    let url: URL
    let bookmark: Data
}

actor FolderStore {
    let supportURL: URL
    private let configurationURL: URL

    init(supportURL: URL = FolderStore.defaultSupportURL) {
        self.supportURL = supportURL
        configurationURL = supportURL.appendingPathComponent("configuration.json")
    }

    static var defaultSupportURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DictationBar", isDirectory: true)
    }

    func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            return AppConfiguration()
        }
        return try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: configurationURL))
    }

    func save(_ configuration: AppConfiguration) throws {
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)
        if let existing = try? Data(contentsOf: configurationURL),
           (try? JSONDecoder().decode(AppConfiguration.self, from: existing)) == nil {
            try existing.write(to: supportURL.appendingPathComponent("configuration-damaged-\(UUID()).json"), options: .withoutOverwriting)
        }
        try JSONEncoder().encode(configuration).write(to: configurationURL, options: .atomic)
    }

    func makeBookmark(for folder: URL) throws -> Data { try Self.bookmark(for: folder) }
    func resolvedFolder(_ bookmark: Data?) throws -> ResolvedFolder { try Self.resolve(bookmark) }

    static func bookmark(for folder: URL) throws -> Data {
        try checkDirectory(folder)
        return try folder.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    static func resolve(_ bookmark: Data?) throws -> ResolvedFolder {
        guard let bookmark else { throw LocalStoreError.missingFolder }
        var stale = false
        let url: URL
        do {
            url = try URL(resolvingBookmarkData: bookmark, options: [.withoutUI, .withoutMounting],
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        } catch { throw LocalStoreError.invalidFolder }
        try checkDirectory(url)
        return ResolvedFolder(url: url, bookmark: stale ? try Self.bookmark(for: url) : bookmark)
    }

    private static func checkDirectory(_ url: URL) throws {
        guard url.isFileURL,
              (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw LocalStoreError.invalidFolder
        }
    }
}
