import Foundation
import Security

// MARK: - Storage key constants

enum FolioStorageKey {
    static let activeEnvironment = "folio.activeEnvironment"
    static let devBaseURL = "folio.dev.baseURL"
    static let prodBaseURL = "folio.prod.baseURL"
    static let devApiKey = "folio.dev.apiKey"
    static let prodApiKey = "folio.prod.apiKey"
}

// MARK: - Keychain

enum KeychainService {
    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
        case dataEncodingFailed
        case dataDecodingFailed
    }

    static func save(_ value: String, key: String) throws(KeychainError) {
        guard let data = value.data(using: .utf8) else { throw .dataEncodingFailed }

        let deleteQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw .unexpectedStatus(status) }
    }

    static func read(key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func delete(key: String) {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
