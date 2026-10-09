import XCTest
@testable import DictationBar

final class MistralTranscriptionTests: XCTestCase {
    func testMultipartContractUsesWAVAndExplicitModelWithOneTaskAndNoConstructorAccess() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let file = f.folder.appendingPathComponent("audio.wav")
        let audio = LocalStoreFixture.wav(); try audio.write(to: file)
        let key = TestKeyStore()
        let transport = TestUploadTransport()
        let service = MistralTranscriptionService(keys: key, transport: transport, temporaryDirectory: f.root)
        let callsBefore = await key.reads
        XCTAssertEqual(callsBefore, 0)
        let text = try await service.transcribe(file: file)
        XCTAssertEqual(text, "Grüße 🌱")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.url?.absoluteString, "https://api.mistral.ai/v1/audio/transcriptions")
        XCTAssertEqual(requests.first?.httpMethod, "POST")
        XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "Bearer local-test-key")
        let body = await transport.bodies.first ?? Data()
        XCTAssertNotNil(body.range(of: audio))
        let header = String(decoding: body.prefix(420), as: UTF8.self)
        XCTAssertTrue(header.contains("voxtral-mini-latest"))
        XCTAssertTrue(header.contains("name=\"stream\"\r\n\r\nfalse"))
        XCTAssertTrue(header.contains("Content-Type: audio/wav"))
        let files = try FileManager.default.contentsOfDirectory(at: f.root, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.contains { $0.lastPathComponent.hasPrefix("DictationBar-upload-") })
        XCTAssertEqual(try Data(contentsOf: file), audio)
    }

    func testHTTPAndMalformedResponsesNeverRetryAndKeepWAV() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let file = f.folder.appendingPathComponent("audio.wav")
        try LocalStoreFixture.wav().write(to: file)
        let cases: [(Int, Data, TranscriptionFailure)] = [
            (401, Data(), .invalidKey), (429, Data(), .rateLimited), (503, Data(), .server),
            (200, Data("{\"text\":\"  \"}".utf8), .invalidResponse),
            (200, Data("{\"other\":1}".utf8), .invalidResponse),
            (200, Data(repeating: 0, count: 4 * 1_024 * 1_024 + 1), .invalidResponse)
        ]
        for (status, body, expected) in cases {
            let transport = TestUploadTransport(response: HTTPUploadResponse(status: status, body: body))
            let service = MistralTranscriptionService(keys: TestKeyStore(), transport: transport, temporaryDirectory: f.root)
            do { _ = try await service.transcribe(file: file); XCTFail("Expected error") }
            catch { XCTAssertEqual(error as? TranscriptionFailure, expected) }
            let requests = await transport.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        }
    }

    func testMissingKeyAndInvalidWAVPreventAnyUpload() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let file = f.folder.appendingPathComponent("audio.wav")
        try LocalStoreFixture.wav().write(to: file)
        let transport = TestUploadTransport()
        let key = TestKeyStore(error: .missing)
        let service = MistralTranscriptionService(keys: key, transport: transport, temporaryDirectory: f.root)
        do { _ = try await service.transcribe(file: file); XCTFail("Expected missing") }
        catch { XCTAssertEqual(error as? APIKeyFailure, .missing) }
        try Data().write(to: file)
        do { _ = try await service.transcribe(file: file); XCTFail("Expected invalid WAV") }
        catch { }
        let requests = await transport.requests
        let reads = await key.reads
        XCTAssertEqual(requests.count, 0)
        XCTAssertEqual(reads, 1)
    }
    func testSourceDisappearingDuringKeyReadLeavesNoMultipartTemporaryFile() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let file = f.folder.appendingPathComponent("audio.wav")
        try LocalStoreFixture.wav().write(to: file)
        let transport = TestUploadTransport()
        let keys = TestKeyStore(onRead: { try FileManager.default.removeItem(at: file) })
        let service = MistralTranscriptionService(keys: keys, transport: transport, temporaryDirectory: f.root)
        do { _ = try await service.transcribe(file: file); XCTFail("Missing source must fail") }
        catch { }
        let files = try FileManager.default.contentsOfDirectory(at: f.root, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.contains { $0.lastPathComponent.hasPrefix("DictationBar-upload-") })
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testCancellationRemovesMultipartAndRetainsOriginalWAV() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let file = f.folder.appendingPathComponent("audio.wav")
        let audio = LocalStoreFixture.wav(); try audio.write(to: file)
        let service = MistralTranscriptionService(keys: TestKeyStore(), transport: CancelledUpload(), temporaryDirectory: f.root)
        do { _ = try await service.transcribe(file: file); XCTFail("Expected cancellation") }
        catch { XCTAssertEqual(error as? TranscriptionFailure, .cancelled) }
        let files = try FileManager.default.contentsOfDirectory(at: f.root, includingPropertiesForKeys: nil)
        XCTAssertFalse(files.contains { $0.lastPathComponent.hasPrefix("DictationBar-upload-") })
        XCTAssertEqual(try Data(contentsOf: file), audio)
    }

}

actor TestKeyStore: APIKeyStoring {
    var reads = 0
    var value: String?
    let error: APIKeyFailure?
    let onRead: (() throws -> Void)?
    init(error: APIKeyFailure? = nil, value: String? = "local-test-key", onRead: (() throws -> Void)? = nil) { self.error = error; self.value = value; self.onRead = onRead }
    func hasKey() -> Bool { value != nil }
    func read() throws -> String {
        reads += 1
        try onRead?()
        if let error { throw error }
        guard let value else { throw APIKeyFailure.missing }; return value
    }
    func save(_ key: String) { value = key }
    func remove() { value = nil }
}

private actor TestUploadTransport: HTTPUploading {
    var requests: [URLRequest] = []
    var bodies: [Data] = []
    let response: HTTPUploadResponse
    init(response: HTTPUploadResponse = HTTPUploadResponse(status: 200, body: Data("{\"text\":\"Grüße 🌱\"}".utf8))) {
        self.response = response
    }
    func upload(request: URLRequest, bodyFile: URL) throws -> HTTPUploadResponse {
        requests.append(request); bodies.append(try Data(contentsOf: bodyFile)); return response
    }
    func cancel() { }
}

private actor CancelledUpload: HTTPUploading {
    func upload(request: URLRequest, bodyFile: URL) throws -> HTTPUploadResponse { throw CancellationError() }
    func cancel() { }
}
