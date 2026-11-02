import Foundation
import Security
import Synchronization

/// What survives a relaunch: the tokens and the Client ID they were issued to.
public struct StoredCredentials: Codable, Hashable, Sendable {
    public var clientID: String
    public var tokens: OAuthTokens

    public init(clientID: String, tokens: OAuthTokens) {
        self.clientID = clientID
        self.tokens = tokens
    }
}

public protocol CredentialStore: Sendable {
    func load() -> StoredCredentials?
    func save(_ credentials: StoredCredentials)
    func delete()
}

/// Tokens live only in the Keychain (generic password, this device only).
public struct KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account = "x-oauth2"

    public init(service: String = "dev.frnoch.liquidx") {
        self.service = service
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> StoredCredentials? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(StoredCredentials.self, from: data)
    }

    public func save(_ credentials: StoredCredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }

    public func delete() {
        SecItemDelete(query as CFDictionary)
    }
}

/// In-memory store for tests and UI-test runs.
public final class EphemeralCredentialStore: CredentialStore {
    private let storage = Mutex<StoredCredentials?>(nil)

    public init(_ credentials: StoredCredentials? = nil) {
        storage.withLock { $0 = credentials }
    }

    public func load() -> StoredCredentials? { storage.withLock { $0 } }
    public func save(_ credentials: StoredCredentials) { storage.withLock { $0 = credentials } }
    public func delete() { storage.withLock { $0 = nil } }
}
