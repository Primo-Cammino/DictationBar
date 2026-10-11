import AVFoundation
import AudioToolbox
import Darwin
import Foundation

struct WAVInfo: Equatable {
    let duration: TimeInterval
    let frames: Int64
}

enum WAVValidator {
    static func inspect(_ url: URL) throws -> WAVInfo {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 12) ?? Data()
        guard header.count == 12,
              String(data: header.prefix(4), encoding: .ascii) == "RIFF",
              String(data: header.suffix(4), encoding: .ascii) == "WAVE" else {
            throw LocalStoreError.invalidWAV
        }
        let file: AVAudioFile
        do { file = try AVAudioFile(forReading: url) }
        catch {
            let failure = error as NSError
            let structuralCodes = [kAudioFileInvalidFileError, kAudioFileInvalidChunkError,
                                   kAudioFileUnsupportedFileTypeError, kAudioFileUnsupportedDataFormatError]
            // AVAudioFile reports AudioFile statuses through AVFAudio on this OS;
            // the lower-level API can report the same codes as OSStatus errors.
            if [NSOSStatusErrorDomain, "com.apple.coreaudio.avfaudio"].contains(failure.domain),
               structuralCodes.contains(where: { Int($0) == failure.code }) {
                throw LocalStoreError.invalidWAV
            }
            throw error
        }
        let settings = file.fileFormat.settings
        guard file.length > 0, file.fileFormat.sampleRate == 48_000,
              file.fileFormat.channelCount == 1,
              (settings[AVFormatIDKey] as? UInt32) == kAudioFormatLinearPCM,
              (settings[AVLinearPCMBitDepthKey] as? Int) == 16,
              (settings[AVLinearPCMIsFloatKey] as? Bool) != true else {
            throw LocalStoreError.invalidWAV
        }
        return WAVInfo(duration: Double(file.length) / 48_000, frames: file.length)
    }
}

struct RecordingPaths {
    let staging: URL
    let final: URL
    var reservation: StagingReservation?
}

struct StagingReservation {
    let inode: UInt64
    let device: Int32

    /// AVFoundation refuses existing output files. Release only this operation's
    /// still-empty reservation; AVFoundation itself rejects a later collision.
    func release(at url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0, info.st_ino == inode,
              info.st_dev == device, info.st_size == 0,
              (info.st_mode & S_IFMT) == S_IFREG else { throw LocalStoreError.collision }
        guard unlink(url.path) == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
}

actor RecordingStore {
    let history: HistoryStore
    private let inspect: (URL) throws -> WAVInfo
    private let beforeRename: () throws -> Void

    init(history: HistoryStore, inspect: @escaping (URL) throws -> WAVInfo = WAVValidator.inspect,
         beforeRename: @escaping () throws -> Void = {}) {
        self.history = history
        self.inspect = inspect
        self.beforeRename = beforeRename
    }

    func paths(for entry: HistoryEntry) throws -> RecordingPaths {
        let folder = try FolderStore.resolve(entry.folderBookmark).url
        return RecordingPaths(staging: folder.appendingPathComponent(entry.stagingFilename),
                              final: folder.appendingPathComponent(entry.filename))
    }

    func prepare(_ entry: HistoryEntry, token: OperationToken) async throws -> RecordingPaths {
        var paths = try paths(for: entry)
        guard !FileManager.default.fileExists(atPath: paths.final.path) else {
            throw LocalStoreError.collision
        }
        await history.authorize(token)
        try await history.create(entry, token: token)
        // A reserved staging path prevents an existing user's file being opened.
        let fd = open(paths.staging.path, O_WRONLY | O_CREAT | O_EXCL, S_IRUSR | S_IWUSR)
        guard fd >= 0 else {
            if errno == EEXIST { throw LocalStoreError.collision }
            throw CocoaError(.fileWriteUnknown)
        }
        var info = stat()
        guard fstat(fd, &info) == 0 else { close(fd); throw CocoaError(.fileWriteUnknown) }
        paths.reservation = StagingReservation(inode: info.st_ino, device: info.st_dev)
        close(fd)
        var prepared = entry
        prepared.stagingOwned = true
        try await history.save(prepared, token: token)
        return paths
    }

    func finalize(_ entry: HistoryEntry, token: OperationToken, interrupted: Bool) async throws -> HistoryEntry {
        let paths = try paths(for: entry)
        let info = try inspect(paths.staging)
        try beforeRename()
        try Self.moveExclusively(from: paths.staging, to: paths.final)
        var saved = entry
        saved.stagingOwned = true
        saved.duration = info.duration
        saved.status = interrupted ? .interrupted : .pending
        saved.message = interrupted ? "Aufnahme unterbrochen. Transkription bitte bewusst starten." : nil
        try await history.save(saved, token: token)
        return saved
    }

    func readableWAV(for entry: HistoryEntry) throws -> URL {
        let paths = try paths(for: entry)
        _ = try inspect(paths.final)
        return paths.final
    }

    func completeCheckpoint(_ entry: HistoryEntry, token: OperationToken) async throws -> HistoryEntry {
        let paths = try paths(for: entry)
        if FileManager.default.fileExists(atPath: paths.final.path) {
            guard !FileManager.default.fileExists(atPath: paths.staging.path) else { throw LocalStoreError.collision }
            let info = try inspect(paths.final)
            var saved = entry
            saved.duration = info.duration
            saved.status = .interrupted
            saved.message = "Aufnahme gesichert. Transkription bitte bewusst starten."
            try await history.save(saved, token: token)
            return saved
        }
        return try await finalize(entry, token: token, interrupted: true)
    }

    func recover() async throws -> HistorySnapshot {
        let snapshot = try await history.load()
        var warnings = snapshot.warnings
        for original in snapshot.entries {
            var entry = original
            do {
                let paths = try paths(for: entry)
                let staging = FileManager.default.fileExists(atPath: paths.staging.path)
                let final = FileManager.default.fileExists(atPath: paths.final.path)
                guard !(staging && final) else { throw LocalStoreError.collision }
                if staging {
                    guard entry.stagingOwned == true else { throw LocalStoreError.collision }
                    try Self.repairHeader(at: paths.staging)
                    let info = try inspect(paths.staging)
                    try beforeRename()
                    try Self.moveExclusively(from: paths.staging, to: paths.final)
                    entry.duration = info.duration
                    entry.status = entry.transcript == nil ? .interrupted : .complete
                    entry.message = "Aufnahme nach Unterbrechung gesichert."
                } else if final {
                    let info = try inspect(paths.final)
                    entry.duration = info.duration
                    if entry.transcript != nil { entry.status = .complete }
                    else if entry.status != .failed && entry.status != .interrupted { entry.status = .pending }
                    if entry.status == .pending { entry.message = nil }
                } else {
                    entry.status = entry.transcript == nil ? .failed : .complete
                    entry.message = "Audiodatei fehlt. Vorhandener Text bleibt kopierbar."
                }
            } catch {
                entry.status = entry.transcript == nil ? .failed : .complete
                entry.message = "Lokale Aufnahme konnte nicht wiederhergestellt werden. Vorhandene Dateien bleiben erhalten."
            }
            if entry != original {
                do { try await history.saveRecovered(entry) }
                catch { warnings.append("Wiederhergestellter History-Status konnte nicht gespeichert werden.") }
            }
        }
        let loaded = try await history.load()
        return HistorySnapshot(entries: loaded.entries, warnings: warnings)
    }

    /// A crash leaves PCMRecordingWriter's header with size 0. Rebuild it from
    /// the file length, cut to whole frames, without reading the audio.
    private static func repairHeader(at url: URL) throws {
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard size > 44, size - 44 <= UInt64(UInt32.max - 36) else { return }
        try handle.seek(toOffset: 0)
        let existing = try handle.read(upToCount: 44) ?? Data()
        let dataBytes = (size - 44) / 2 * 2
        let expected = PCMRecordingWriter.header(dataBytes: UInt32(dataBytes))
        // Only the writer's own layout is repaired; any other file goes to inspect unchanged.
        guard existing.count == 44, existing.prefix(4) == expected.prefix(4),
              existing[8..<40] == expected[8..<40] else { return }
        if dataBytes + 44 != size { try handle.truncate(atOffset: dataBytes + 44) }
        guard existing != expected else { return }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: expected)
        try handle.synchronize()
    }

    private static func moveExclusively(from source: URL, to destination: URL) throws {
        guard renamex_np(source.path, destination.path, UInt32(RENAME_EXCL)) == 0 else {
            if errno == EEXIST { throw LocalStoreError.collision }
            throw CocoaError(.fileWriteUnknown)
        }
    }
}
