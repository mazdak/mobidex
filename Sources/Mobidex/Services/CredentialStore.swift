import Foundation
import Security

enum CredentialStoreError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "Could not encode the credential."
        case .decodingFailed:
            "Could not decode the saved credential."
        case .keychain(let status):
            "Keychain error \(status)."
        }
    }
}

protocol CredentialStore: Sendable {
    func loadCredential(serverID: UUID) throws -> SSHCredential
    func saveCredential(_ credential: SSHCredential, serverID: UUID) throws
    func deleteCredential(serverID: UUID) throws
    func loadOpenAIAPIKey() throws -> String?
    func saveOpenAIAPIKey(_ key: String?) throws
    func loadXAIAPIKey() throws -> String?
    func saveXAIAPIKey(_ key: String?) throws
}

final class KeychainCredentialStore: CredentialStore, @unchecked Sendable {
    private let service = "com.getresq.mobidex.ssh"
    private let appAccountID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    func loadCredential(serverID: UUID) throws -> SSHCredential {
        SSHCredential(
            password: try read(kind: "password", serverID: serverID),
            privateKeyPEM: try read(kind: "private-key", serverID: serverID),
            privateKeyPassphrase: try read(kind: "private-key-passphrase", serverID: serverID)
        )
    }

    func saveCredential(_ credential: SSHCredential, serverID: UUID) throws {
        try write(credential.password, kind: "password", serverID: serverID)
        try write(credential.privateKeyPEM, kind: "private-key", serverID: serverID)
        try write(credential.privateKeyPassphrase, kind: "private-key-passphrase", serverID: serverID)
        try delete(kind: "app-server-auth-token", serverID: serverID)
    }

    func deleteCredential(serverID: UUID) throws {
        try delete(kind: "password", serverID: serverID)
        try delete(kind: "private-key", serverID: serverID)
        try delete(kind: "private-key-passphrase", serverID: serverID)
        try delete(kind: "app-server-auth-token", serverID: serverID)
    }

    func loadOpenAIAPIKey() throws -> String? {
        try read(kind: "openai-api-key", serverID: appAccountID)
    }

    func saveOpenAIAPIKey(_ key: String?) throws {
        try write(key, kind: "openai-api-key", serverID: appAccountID)
    }

    func loadXAIAPIKey() throws -> String? {
        try read(kind: "xai-api-key", serverID: appAccountID)
    }

    func saveXAIAPIKey(_ key: String?) throws {
        try write(key, kind: "xai-api-key", serverID: appAccountID)
    }

    private func account(kind: String, serverID: UUID) -> String {
        "\(serverID.uuidString).\(kind)"
    }

    private func read(kind: String, serverID: UUID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(kind: kind, serverID: serverID),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.decodingFailed
        }
        return value
    }

    private func write(_ value: String?, kind: String, serverID: UUID) throws {
        guard let value, !value.isEmpty else {
            try delete(kind: kind, serverID: serverID)
            return
        }
        guard let data = value.data(using: .utf8) else {
            throw CredentialStoreError.encodingFailed
        }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(kind: kind, serverID: serverID)
        ]
        let updateStatus = SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw CredentialStoreError.keychain(updateStatus)
        }

        var add = base
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychain(addStatus)
        }
    }

    private func delete(kind: String, serverID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(kind: kind, serverID: serverID)
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }
}

final class InMemoryCredentialStore: CredentialStore, @unchecked Sendable {
    private var values: [UUID: SSHCredential] = [:]
    private var openAIAPIKey: String?
    private let lock = NSLock()

    func loadCredential(serverID: UUID) throws -> SSHCredential {
        lock.withLock { values[serverID] ?? SSHCredential() }
    }

    func saveCredential(_ credential: SSHCredential, serverID: UUID) throws {
        lock.withLock {
            values[serverID] = credential
        }
    }

    func deleteCredential(serverID: UUID) throws {
        lock.withLock {
            _ = values.removeValue(forKey: serverID)
        }
    }

    func loadOpenAIAPIKey() throws -> String? {
        lock.withLock { openAIAPIKey }
    }

    func saveOpenAIAPIKey(_ key: String?) throws {
        lock.withLock {
            openAIAPIKey = key?.isEmpty == false ? key : nil
        }
    }

    private var xaiAPIKey: String?

    func loadXAIAPIKey() throws -> String? {
        lock.withLock { xaiAPIKey }
    }

    func saveXAIAPIKey(_ key: String?) throws {
        lock.withLock {
            xaiAPIKey = key?.isEmpty == false ? key : nil
        }
    }
}
