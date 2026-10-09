import Foundation
import LocalAuthentication
import Security

struct KeychainOperations {
    let copy: ([String: Any]) -> (OSStatus, CFTypeRef?)
    let add: ([String: Any]) -> OSStatus
    let update: ([String: Any], [String: Any]) -> OSStatus
    let delete: ([String: Any]) -> OSStatus

    static let native = KeychainOperations(copy: { query in
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }, add: { SecItemAdd($0 as CFDictionary, nil) }, update: {
        SecItemUpdate($0 as CFDictionary, $1 as CFDictionary)
    }, delete: { SecItemDelete($0 as CFDictionary) })
}

actor NativeKeychainStore: APIKeyStoring {
    private let operations: KeychainOperations
    private let identity: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.primocammino.DictationBar.mistral",
        kSecAttrAccount as String: "api-key",
        kSecAttrSynchronizable as String: false
    ]

    init(operations: KeychainOperations = .native) { self.operations = operations }

    func hasKey() throws -> Bool {
        var query = identity
        query[kSecReturnAttributes as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, _) = operations.copy(query)
        if status == errSecItemNotFound { return false }
        try check(status)
        return true
    }

    func read() throws -> String {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, value) = operations.copy(query)
        if status == errSecItemNotFound { throw APIKeyFailure.missing }
        try check(status)
        guard let data = value as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { throw APIKeyFailure.storage }
        return key
    }

    func save(_ key: String) throws {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw APIKeyFailure.invalid }
        let changes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        let status = operations.update(identity, changes)
        if status == errSecItemNotFound {
            var item = identity
            item[kSecValueData as String] = Data(value.utf8)
            try check(operations.add(item))
        } else { try check(status) }
    }

    func remove() throws {
        let status = operations.delete(identity)
        if status != errSecItemNotFound { try check(status) }
    }

    private func check(_ status: OSStatus) throws {
        guard status != errSecInteractionNotAllowed, status != errSecAuthFailed,
              status != errSecUserCanceled else { throw APIKeyFailure.locked }
        guard status == errSecSuccess else { throw APIKeyFailure.storage }
    }
}
