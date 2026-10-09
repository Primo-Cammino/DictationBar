import XCTest
@testable import DictationBar

final class RecordingServiceTests: XCTestCase {
    @MainActor
    func testSelectedDeviceAndDelayedFinalizationWithDuplicateStop() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let paths = RecordingPaths(staging: f.folder.appendingPathComponent("stage"), final: f.folder.appendingPathComponent("final"))
        let fake = FakeCaptureDriver()
        var selected: String?
        let service = RecordingService { id, _, event in selected = id; fake.event = event; return fake }
        let starting = Task { try await service.start(microphoneID: "chosen-device", paths: paths) }
        await Task.yield()
        XCTAssertEqual(selected, "chosen-device")
        XCTAssertTrue(service.isActive)
        fake.event?(.started)
        try await starting.value
        let first = Task { try await service.stop() }
        await Task.yield()
        let second = Task { try await service.stop() }
        await Task.yield()
        XCTAssertEqual(fake.stops, 1)
        XCTAssertTrue(service.isActive)
        fake.event?(.finished(CaptureCompletion(interrupted: false)))
        let result = try await first.value
        _ = try await second.value
        XCTAssertFalse(result.interrupted)
        XCTAssertFalse(service.isActive)
        fake.event?(.finished(CaptureCompletion(interrupted: true)))
        let cached = try await service.stop()
        XCTAssertEqual(cached, result)
    }

    @MainActor
    func testMissingCallbackTimesOutWithoutClaimingShutdownOrAllowingNewCapture() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let paths = RecordingPaths(staging: f.folder.appendingPathComponent("stage"), final: f.folder.appendingPathComponent("final"))
        let fake = FakeCaptureDriver()
        let service = RecordingService(deadlineNanoseconds: 1_000_000) { _, _, event in fake.event = event; return fake }
        do { try await service.start(microphoneID: "chosen", paths: paths); XCTFail("Expected timeout") }
        catch { XCTAssertTrue(service.isActive) }
        do { try await service.start(microphoneID: "other", paths: paths); XCTFail("Expected busy") }
        catch { XCTAssertEqual(fake.starts, 1) }
        fake.event?(.finished(CaptureCompletion(interrupted: true)))
        await Task.yield()
        XCTAssertFalse(service.isActive)
    }

    @MainActor
    func testUnexpectedFinishNotifiesInterruptionOnce() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let paths = RecordingPaths(staging: f.folder.appendingPathComponent("stage"), final: f.folder.appendingPathComponent("final"))
        let fake = FakeCaptureDriver()
        let service = RecordingService { _, _, event in fake.event = event; return fake }
        var interruptions = 0
        service.onInterruption = { interruptions += 1 }
        let starting = Task { try await service.start(microphoneID: "chosen", paths: paths) }
        await Task.yield(); fake.event?(.started); try await starting.value
        fake.event?(.finished(CaptureCompletion(interrupted: true)))
        fake.event?(.finished(CaptureCompletion(interrupted: true)))
        await Task.yield()
        XCTAssertEqual(interruptions, 1)
    }

    func testNonEmptyReservationIsNeverRemoved() async throws {
        let f = try LocalStoreFixture(); defer { f.cleanup() }
        let store = RecordingStore(history: HistoryStore(supportURL: f.support))
        let entry = try f.entry()
        let paths = try await store.prepare(entry, token: f.token(entry))
        let bytes = Data("Existing data".utf8); try bytes.write(to: paths.staging)
        XCTAssertThrowsError(try paths.reservation?.release(at: paths.staging))
        XCTAssertEqual(try Data(contentsOf: paths.staging), bytes)
    }
}

private final class FakeCaptureDriver: CaptureDriving {
    var event: ((CaptureEvent) -> Void)?
    var starts = 0
    var stops = 0
    func start() { starts += 1 }
    func stop() { stops += 1 }
}
