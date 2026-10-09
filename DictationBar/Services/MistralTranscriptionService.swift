import Foundation

actor MistralTranscriptionService: TranscriptionProviding {
    private let keys: any APIKeyStoring
    private let transport: any HTTPUploading
    private let temporaryDirectory: URL

    init(keys: any APIKeyStoring, transport: any HTTPUploading = NativeHTTPTransport(),
         temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.keys = keys
        self.transport = transport
        self.temporaryDirectory = temporaryDirectory
    }

    func transcribe(file: URL) async throws -> String {
        let info = try WAVValidator.inspect(file)
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard info.duration <= 3_600, size > 0, size <= 500_000_000 else { throw TranscriptionFailure.tooLarge }
        let key = try await keys.read()
        try Task.checkCancellation()
        let boundary = "DictationBar-\(UUID().uuidString)"
        let body = temporaryDirectory.appendingPathComponent("DictationBar-upload-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: body) }
        try writeMultipart(file: file, destination: body, boundary: boundary)
        var request = URLRequest(url: URL(string: "https://api.mistral.ai/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response: HTTPUploadResponse
        do { response = try await transport.upload(request: request, bodyFile: body) }
        catch is CancellationError { throw TranscriptionFailure.cancelled }
        catch let error as TranscriptionFailure { throw error }
        catch { throw TranscriptionFailure.network }
        try Task.checkCancellation()
        switch response.status {
        case 200..<300: break
        case 401, 403: throw TranscriptionFailure.invalidKey
        case 429: throw TranscriptionFailure.rateLimited
        default: throw TranscriptionFailure.server
        }
        struct Payload: Decodable { let text: String }
        guard response.body.count <= 4 * 1_024 * 1_024,
              let payload = try? JSONDecoder().decode(Payload.self, from: response.body) else {
            throw TranscriptionFailure.invalidResponse
        }
        let text = payload.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionFailure.invalidResponse }
        return text
    }

    func verifyKey() async throws -> Int {
        let key = try await keys.read()
        var request = URLRequest(url: URL(string: "https://api.mistral.ai/v1/models")!)
        request.timeoutInterval = 15
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            let (_, response) = try await session.data(for: request, delegate: RefuseRedirects())
            return (response as? HTTPURLResponse)?.statusCode ?? 0
        } catch { throw TranscriptionFailure.network }
    }

    func cancel() async { await transport.cancel() }

    private func writeMultipart(file: URL, destination: URL, boundary: String) throws {
        try Data().write(to: destination, options: .withoutOverwriting)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        do {
            func write(_ value: String) throws { try output.write(contentsOf: Data(value.utf8)) }
            try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nvoxtral-mini-latest\r\n")
            try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"stream\"\r\n\r\nfalse\r\n")
            try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
            while let chunk = try input.read(upToCount: 64 * 1_024), !chunk.isEmpty {
                try output.write(contentsOf: chunk)
            }
            try write("\r\n--\(boundary)--\r\n")
            try output.synchronize()
        } catch {
            try? output.close()
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }
}

/// The key must never follow a redirect to another host.
private final class RefuseRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

/// Creates exactly one native task per explicit request. Constructors do not
/// create URLSessions; redirects are refused and responses are bounded in RAM.
final class NativeHTTPTransport: HTTPUploading, @unchecked Sendable {
    private let lock = NSLock()
    private var current: UploadOperation?

    func upload(request: URLRequest, bodyFile: URL) async throws -> HTTPUploadResponse {
        let operation = UploadOperation()
        setCurrent(operation)
        defer { clearCurrent(operation) }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                operation.start(request: request, bodyFile: bodyFile, continuation: continuation)
            }
        } onCancel: { operation.cancel() }
    }

    func cancel() async {
        lockedCurrent()?.cancel()
    }

    private func setCurrent(_ operation: UploadOperation) {
        lock.lock(); defer { lock.unlock() }
        current = operation
    }
    private func clearCurrent(_ operation: UploadOperation) {
        lock.lock(); defer { lock.unlock() }
        if current === operation { current = nil }
    }
    private func lockedCurrent() -> UploadOperation? {
        lock.lock(); defer { lock.unlock() }; return current
    }
}

private final class UploadOperation: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let queue: OperationQueue = {
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; return queue
    }()
    private var session: URLSession?
    private var task: URLSessionUploadTask?
    private var continuation: CheckedContinuation<HTTPUploadResponse, Error>?
    private var data = Data()
    private var status: Int?
    private var cancelled = false
    private var finished = false
    private let limit = 4 * 1_024 * 1_024

    func start(request: URLRequest, bodyFile: URL, continuation: CheckedContinuation<HTTPUploadResponse, Error>) {
        queue.addOperation { [self] in
            self.continuation = continuation
            guard !cancelled else { complete(.failure(CancellationError())); return }
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 120
            configuration.timeoutIntervalForResource = 900
            configuration.waitsForConnectivity = false
            configuration.httpShouldSetCookies = false
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
            self.session = session
            let task = session.uploadTask(with: request, fromFile: bodyFile)
            self.task = task
            task.resume()
        }
    }

    func cancel() {
        queue.addOperation { [self] in
            cancelled = true
            task?.cancel()
            if continuation != nil { complete(.failure(CancellationError())) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard response.expectedContentLength <= Int64(limit),
              let response = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            complete(.failure(TranscriptionFailure.invalidResponse))
            return
        }
        status = response.statusCode
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }
        guard self.data.count + data.count <= limit else {
            task?.cancel()
            complete(.failure(TranscriptionFailure.invalidResponse))
            return
        }
        self.data.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { complete(.failure(error)) }
        else if let status { complete(.success(HTTPUploadResponse(status: status, body: data))) }
        else { complete(.failure(TranscriptionFailure.invalidResponse)) }
    }

    private func complete(_ result: Result<HTTPUploadResponse, Error>) {
        guard !finished else { return }
        finished = true
        let waiter = continuation; continuation = nil
        session?.invalidateAndCancel()
        session = nil; task = nil
        waiter?.resume(with: result)
    }
}
