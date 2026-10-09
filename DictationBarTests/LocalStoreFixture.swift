import Foundation
@testable import DictationBar

final class LocalStoreFixture {
    let root: URL
    let folder: URL
    let support: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("DictationBarTests-\(UUID())")
        folder = root.appendingPathComponent("audio", isDirectory: true)
        support = root.appendingPathComponent("support", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func cleanup() { try? FileManager.default.removeItem(at: root) }

    func entry(id: UUID = UUID(), date: Date = Date()) throws -> HistoryEntry {
        HistoryEntry(id: id, createdAt: date, microphoneID: "test-microphone",
                     folderBookmark: try FolderStore.bookmark(for: folder))
    }

    func token(_ entry: HistoryEntry, generation: UInt64 = 1) -> OperationToken {
        OperationToken(id: entry.id, generation: generation, origin: .liveDictation)
    }

    static func wav(frames: Int = 480, sampleRate: Int = 48_000, bits: Int = 16) -> Data {
        var data = Data()
        func ascii(_ value: String) { data.append(contentsOf: value.utf8) }
        func u16(_ value: Int) { var n = UInt16(value).littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        func u32(_ value: Int) { var n = UInt32(value).littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        let bytes = frames * bits / 8
        ascii("RIFF"); u32(36 + bytes); ascii("WAVEfmt "); u32(16)
        u16(1); u16(1); u32(sampleRate); u32(sampleRate * bits / 8); u16(bits / 8); u16(bits)
        ascii("data"); u32(bytes); data.append(Data(repeating: 0, count: bytes))
        return data
    }
}
