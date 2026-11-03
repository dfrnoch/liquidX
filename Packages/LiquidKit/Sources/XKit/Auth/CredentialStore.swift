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

/// Persists one Codable credential value.
public protocol SecretStore<Value>: Sendable {
    associatedtype Value: Codable & Sendable
    func load() -> Value?
    func save(_ value: Value)
    func delete()
}

public typealias CredentialStore = SecretStore<StoredCredentials>

/// A generic-password Keychain item, this device only.
public struct KeychainStore<Value: Codable & Sendable>: SecretStore {
    private let service: String
    private let account: String

    public init(service: String = "dev.frnoch.liquidx", account: String) {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func load() -> Value? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
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

/// OAuth tokens for the official API.
public typealias KeychainCredentialStore = KeychainStore<StoredCredentials>

extension KeychainStore where Value == StoredCredentials {
    public init(service: String = "dev.frnoch.liquidx") {
        self.init(service: service, account: "x-oauth2")
    }
}

/// In-memory store for tests and UI-test runs.
public final class EphemeralStore<Value: Codable & Sendable>: SecretStore {
    private let storage = Mutex<Value?>(nil)

    public init(_ value: Value? = nil) {
        storage.withLock { $0 = value }
    }

    public func load() -> Value? { storage.withLock { $0 } }
    public func save(_ value: Value) { storage.withLock { $0 = value } }
    public func delete() { storage.withLock { $0 = nil } }
}

public typealias EphemeralCredentialStore = EphemeralStore<StoredCredentials>

/// Development-only store for ad hoc signed macOS builds: every rebuild gets a
/// new code signature, so the Keychain asks for the login password again on
/// each launch. This keeps the value in a 0600 file inside the app's sandbox
/// container instead, migrating once from the Keychain. Never used in Release.
public struct DevelopmentFileStore<Value: Codable & Sendable>: SecretStore {
    private let url: URL
    private let migrateFrom: KeychainStore<Value>

    public init(account: String, migrateFrom keychain: KeychainStore<Value>) {
        let directory = URL.applicationSupportDirectory.appending(path: "LiquidX-Development", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "\(account).json")
        migrateFrom = keychain
    }

    public func load() -> Value? {
        if let data = try? Data(contentsOf: url) {
            return try? JSONDecoder().decode(Value.self, from: data)
        }
        guard let migrated = migrateFrom.load() else { return nil }
        save(migrated)
        return migrated
    }

    public func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtection])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path())
    }

    public func delete() {
        try? FileManager.default.removeItem(at: url)
        migrateFrom.delete()
    }
}
