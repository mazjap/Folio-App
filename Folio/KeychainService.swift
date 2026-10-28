import Foundation
import Security

// MARK: - Protocol

protocol KeychainStoring {
    func save(_ value: String, key: String) throws(KeychainService.KeychainError)
    func read(key: String) -> String?
    func delete(key: String)
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
                return "The API key couldn't be saved to the Keychain: \(reason)."
            case .dataEncodingFailed:
                return "The API key couldn't be encoded."
            }
        }
    }
    
    func save(_ value: String, key: String) throws(KeychainError) {
        guard let data = value.data(using: .utf8) else { throw .dataEncodingFailed }
        
        delete(key: key)
        
        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw .unexpectedStatus(status) }
    }
    
    func read(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        
        return String(data: data, encoding: .utf8)
    }
    
    func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Test fake

/// An in-memory keychain for tests and previews.
final class TestKeychain: KeychainStoring {
    var values: [String: String]
    /// When set, `save(_:key:)` throws it instead of saving.
    var saveError: KeychainService.KeychainError?
    
    init(values: [String: String] = [:], saveError: KeychainService.KeychainError? = nil) {
        self.values = values
        self.saveError = saveError
    }
    
    func save(_ value: String, key: String) throws(KeychainService.KeychainError) {
        if let saveError { throw saveError }
        
        values[key] = value
    }
    
    func read(key: String) -> String? {
        values[key]
    }
    
    func delete(key: String) {
        values[key] = nil
    }
}
