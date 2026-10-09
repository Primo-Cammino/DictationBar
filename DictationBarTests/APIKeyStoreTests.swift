import Security
import LocalAuthentication
import XCTest
@testable import DictationBar

final class APIKeyStoreTests: XCTestCase {
    func testConstructionIsPassiveAndExplicitSaveUsesNonSynchronizingIdentity() async throws {
        let spy = KeychainSpy()
        let store = NativeKeychainStore(operations: spy.operations)
        XCTAssertEqual(spy.calls, [])
        try await store.save("  local-test-key  ")
        XCTAssertEqual(spy.calls, ["update", "add"])
        XCTAssertEqual(spy.item?[kSecAttrSynchronizable as String] as? Bool, false)
        XCTAssertEqual(spy.item?[kSecValueData as String] as? Data, Data("local-test-key".utf8))
        try await store.remove()
        XCTAssertEqual(spy.calls.last, "delete")
    }

    func testSavingChangedKeyUpdatesExistingItemWithoutAddingAgain() async throws {
        let spy = KeychainSpy()
        let store = NativeKeychainStore(operations: spy.operations)
        try await store.save("first-local-test-key")
        spy.updateStatus = errSecSuccess
        spy.calls = []
        try await store.save("second-local-test-key")
        XCTAssertEqual(spy.calls, ["update"])
        XCTAssertEqual(spy.item?[kSecValueData as String] as? Data, Data("second-local-test-key".utf8))
    }

    func testPassivePresenceQueryCannotReadKeyDataOrOpenAuthenticationDialog() async throws {
        let spy = KeychainSpy()
        let store = NativeKeychainStore(operations: spy.operations)
        let hasKey = try await store.hasKey()
        XCTAssertFalse(hasKey)
        XCTAssertNil(spy.query?[kSecReturnData as String])
        XCTAssertTrue((spy.query?[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true)
    }

    func testMissingAndLockedKeyRemainDistinctAndEmptySaveDoesNotMutateStore() async throws {
        let spy = KeychainSpy()
        let store = NativeKeychainStore(operations: spy.operations)
        do { _ = try await store.read(); XCTFail("Expected missing") }
        catch { XCTAssertEqual(error as? APIKeyFailure, .missing) }
        spy.status = errSecInteractionNotAllowed
        do { _ = try await store.read(); XCTFail("Expected locked") }
        catch { XCTAssertEqual(error as? APIKeyFailure, .locked) }
        spy.calls = []
        do { try await store.save(" \n"); XCTFail("Expected invalid") }
        catch { XCTAssertEqual(error as? APIKeyFailure, .invalid) }
        XCTAssertEqual(spy.calls, [])
    }

    func testFileKeyStoreRoundTripIsUserOnlyAndIgnoresEmptySave() async throws {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: support) }
        let store = FileKeyStore(supportURL: support)
        do { _ = try await store.read(); XCTFail("Expected missing") }
        catch { XCTAssertEqual(error as? APIKeyFailure, .missing) }
        try await store.save("  local-test-key \n")
        let read = try await store.read()
        XCTAssertEqual(read, "local-test-key")
        let file = support.appendingPathComponent("mistral-api-key").path
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: support.path)[.posixPermissions] as? Int, 0o700)
        do { try await store.save(" "); XCTFail("Expected invalid") }
        catch { XCTAssertEqual(error as? APIKeyFailure, .invalid) }
        let unchanged = try await store.read()
        XCTAssertEqual(unchanged, "local-test-key")
        try await store.remove()
        let present = await store.hasKey()
        XCTAssertFalse(present)
        try await store.remove()
    }
}

private final class KeychainSpy {
    var calls: [String] = []
    var status: OSStatus = errSecItemNotFound
    var updateStatus: OSStatus = errSecItemNotFound
    var item: [String: Any]?
    var query: [String: Any]?
    var operations: KeychainOperations {
        KeychainOperations(copy: { [self] query in
            calls.append("copy"); self.query = query; return (status, nil)
        }, add: { [self] item in
            calls.append("add"); self.item = item; return errSecSuccess
        }, update: { [self] _, changes in
            calls.append("update"); item = changes; return updateStatus
        }, delete: { [self] _ in
            calls.append("delete"); return errSecSuccess
        })
    }
}
