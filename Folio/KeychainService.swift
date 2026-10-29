import Foundation
import Security

// MARK: - Protocol

protocol KeychainStoring {
    func save(_ value: String, key: String) throws(KeychainService.KeychainError)
    /// The saved value, or `nil` when there isn't one.
    func read(key: String) throws(KeychainService.KeychainError) -> String?
    /// Deletes the value. Deleting one that isn't there isn't an error.
    func delete(key: String) throws(KeychainService.KeychainError)
}

// MARK: - Keychain

struct KeychainService: KeychainStoring {
    enum KeychainError: Error, LocalizedError, Equatable {
        case unexpectedStatus(OSStatus)
        case dataEncodingFailed
        
        var errorDescription: String? {
            switch self {
            case let .unexpectedStatus(status):
                let reason = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
                return "The Keychain couldn't be used for the API key: \(reason)."
            case .dataEncodingFailed:
                return "The API key couldn't be encoded."
            }
        }
    }
    
    func save(_ value: String, key: String) throws(KeychainError) {
        guard let data = value.data(using: .utf8) else { throw .dataEncodingFailed }
        
        // NOTE: - Update the existing item rather than deleting and re-adding it, so a failure can't leave the old key deleted and the new one unsaved.
        let updateStatus = SecItemUpdate(query(for: key) as CFDictionary, [kSecValueData: data] as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = query(for: key)
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw .unexpectedStatus(addStatus) }
        default:
            throw .unexpectedStatus(updateStatus)
        }
    }
    
    func read(key: String) throws(KeychainError) -> String? {
        var readQuery = query(for: key)
        readQuery[kSecReturnData] = true
        readQuery[kSecMatchLimit] = kSecMatchLimitOne
        
        var result: AnyObject?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw .unexpectedStatus(status)
        }
    }
    
    func delete(key: String) throws(KeychainError) {
        let status = SecItemDelete(query(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .unexpectedStatus(status) }
    }
    
    // NOTE: - Items are identified by account alone, as they always have been. Adding a service now would stop matching keys saved without one.
    private func query(for key: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
    }
}

// MARK: - Test fake

/// An in-memory keychain for tests and previews.
final class TestKeychain: KeychainStoring {
    var values: [String: String]
    /// When set, `save(_:key:)` throws it instead of saving, leaving the old value as the real Keychain does.
    var saveError: KeychainService.KeychainError?
    /// When set, `read(key:)` throws it, like a locked Keychain.
    var readError: KeychainService.KeychainError?
    
    init(values: [String: String] = [:], saveError: KeychainService.KeychainError? = nil, readError: KeychainService.KeychainError? = nil) {
        self.values = values
        self.saveError = saveError
        self.readError = readError
    }
    
    func save(_ value: String, key: String) throws(KeychainService.KeychainError) {
        if let saveError { throw saveError }
        
        values[key] = value
    }
    
    func read(key: String) throws(KeychainService.KeychainError) -> String? {
        if let readError { throw readError }
        
        return values[key]
    }
    
    func delete(key: String) throws(KeychainService.KeychainError) {
        values[key] = nil
    }
}
