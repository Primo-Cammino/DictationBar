import Darwin
import Foundation
import XCTest
@testable import DictationBar

final class NativeHTTPTransportTests: XCTestCase {
    func testRedirectRefusesSecondRequestAndRetainsUploadFile() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let server = try LoopbackHTTPFixture(); defer { server.stop() }
        server.start(response: .redirect)
        let file = f.root.appendingPathComponent("neutral-upload.tmp")
        let bytes = Data("neutral fixture".utf8); try bytes.write(to: file)
        var request = URLRequest(url: server.url)
        request.httpMethod = "POST"
        request.setValue(String((try file.resourceValues(forKeys: [.fileSizeKey])).fileSize!), forHTTPHeaderField: "Content-Length")
        request.setValue("Bearer local-fixture-only", forHTTPHeaderField: "Authorization")
        let result = try await NativeHTTPTransport().upload(request: request, bodyFile: file)
        XCTAssertEqual(result.status, 307)
        XCTAssertEqual(server.requestCount, 1)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
    }

    func testNativeTransportBoundsDeclaredAndStreamedResponseBodies() async throws {
        for response in [LoopbackHTTPFixture.Response.declaredOversize, .streamedOversize] {
            let f = try LocalStoreFixture(); defer { f.cleanup() }
            let server = try LoopbackHTTPFixture(); defer { server.stop() }
            server.start(response: response)
            let file = f.root.appendingPathComponent("neutral-upload.tmp")
            try Data("fixture".utf8).write(to: file)
            var request = URLRequest(url: server.url); request.httpMethod = "POST"
        request.setValue(String((try file.resourceValues(forKeys: [.fileSizeKey])).fileSize!), forHTTPHeaderField: "Content-Length")
            do {
                _ = try await NativeHTTPTransport().upload(request: request, bodyFile: file)
                XCTFail("Oversized response must fail")
            } catch { XCTAssertEqual(error as? TranscriptionFailure, .invalidResponse) }
            XCTAssertEqual(server.requestCount, 1)
        }
    }

    func testNativeCancellationSettlesHeldRequestWithoutAnotherUpload() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let server = try LoopbackHTTPFixture(); defer { server.stop() }
        server.start(response: .held)
        let file = f.root.appendingPathComponent("neutral-upload.tmp")
        try Data("fixture".utf8).write(to: file)
        var request = URLRequest(url: server.url); request.httpMethod = "POST"
        request.setValue(String((try file.resourceValues(forKeys: [.fileSizeKey])).fileSize!), forHTTPHeaderField: "Content-Length")
        let transport = NativeHTTPTransport()
        let uploading = Task { try await transport.upload(request: request, bodyFile: file) }
        let deadline = ProcessInfo.processInfo.systemUptime + 3
        while server.requestCount == 0 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { uploading.cancel(); XCTFail("No loopback request"); return }
            try await Task.sleep(nanoseconds: 1_000_000)
        }
        uploading.cancel()
        do { _ = try await uploading.value; XCTFail("Cancellation must fail") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(server.requestCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}

/// A real URLSession transport fixture, bound only to 127.0.0.1 on an OS-chosen
/// port. Requests contain neutral synthetic bytes, never microphone or Keychain data.
private final class LoopbackHTTPFixture: @unchecked Sendable {
    enum Response { case redirect, declaredOversize, streamedOversize, held }
    private let listener: Int32
    private let port: UInt16
    private let lock = NSLock()
    private var stopped = false
    private var count = 0
    private var connection: Int32 = -1
    private let release = DispatchSemaphore(value: 0)
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }
    var url: URL { URL(string: "http://127.0.0.1:\(port)/upload")! }

    init() throws {
        let localListener = socket(AF_INET, SOCK_STREAM, 0)
        listener = localListener
        guard localListener >= 0 else { throw POSIXError(.EIO) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(localListener, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(listener, 4) == 0 else { Darwin.close(listener); throw POSIXError(.EIO) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(localListener, $0, &length) }
        }
        guard named == 0 else { Darwin.close(listener); throw POSIXError(.EIO) }
        port = UInt16(bigEndian: address.sin_port)
    }

    func start(response: Response) {
        DispatchQueue(label: "DictationBarTests.loopback").async { [self] in
            while true {
                let fd = accept(listener, nil, nil)
                guard fd >= 0 else { return }
                lock.lock(); connection = fd; lock.unlock()
                var noSignal: Int32 = 1
                _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
                var timeout = timeval(tv_sec: 3, tv_usec: 0)
                _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var input = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while input.range(of: Data("\r\n\r\n".utf8)) == nil, input.count < 32_768 {
                    let n = recv(fd, &buffer, buffer.count, 0)
                    guard n > 0 else { break }
                    input.append(contentsOf: buffer.prefix(n))
                }
                // Drain the upload before replying: closing with unread request
                // bytes would send a TCP reset and invalidate the response test.
                if let end = input.range(of: Data("\r\n\r\n".utf8)) {
                    let headers = String(decoding: input[..<end.lowerBound], as: UTF8.self)
                    let length = headers.components(separatedBy: "\r\n").first {
                        $0.lowercased().hasPrefix("content-length:")
                    }.flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
                    while input.count - end.upperBound < length {
                        let n = recv(fd, &buffer, buffer.count, 0)
                        guard n > 0 else { break }
                        input.append(contentsOf: buffer.prefix(n))
                    }
                }
                lock.lock(); count += 1; lock.unlock()
                switch response {
                case .redirect:
                    send("HTTP/1.1 307 Temporary Redirect\r\nLocation: http://127.0.0.1:\(port)/unexpected\r\nContent-Length: 0\r\nConnection: close\r\n\r\n", fd: fd)
                case .declaredOversize:
                    send("HTTP/1.1 200 OK\r\nContent-Length: 4194305\r\nConnection: close\r\n\r\n", fd: fd)
                    send(Data(repeating: 65, count: 4_194_305), fd: fd)
                case .streamedOversize:
                    send("HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nConnection: close\r\n\r\n", fd: fd)
                    let chunk = Data(repeating: 65, count: 65_536)
                    for _ in 0..<65 {
                        guard send("10000\r\n", fd: fd), send(chunk, fd: fd), send("\r\n", fd: fd) else { break }
                    }
                    send("0\r\n\r\n", fd: fd)
                case .held: _ = release.wait(timeout: .now() + 4)
                }
                // Let URLSession reject/cancel before closing a deliberately
                // oversized response; avoid manufacturing a truncation error.
                if response == .declaredOversize || response == .streamedOversize {
                    _ = recv(fd, &buffer, buffer.count, 0)
                }
                lock.lock(); connection = -1; let done = stopped; lock.unlock()
                Darwin.close(fd)
                if done { return }
            }
        }
    }

    func stop() {
        lock.lock(); guard !stopped else { lock.unlock(); return }; stopped = true
        if connection >= 0 { _ = shutdown(connection, SHUT_RDWR) }
        _ = shutdown(listener, SHUT_RDWR); Darwin.close(listener)
        lock.unlock(); release.signal()
    }

    @discardableResult private func send(_ text: String, fd: Int32) -> Bool { send(Data(text.utf8), fd: fd) }
    @discardableResult private func send(_ data: Data, fd: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let n = Darwin.send(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
                guard n > 0 else { return false }
                offset += n
            }
            return true
        }
    }
}
