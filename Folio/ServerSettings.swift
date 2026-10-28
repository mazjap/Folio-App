import Foundation

// MARK: - Storage keys

enum FolioStorageKey {
    static let activeEnvironment = "folio.activeEnvironment"
    static let devBaseURL = "folio.dev.baseURL"
    static let prodBaseURL = "folio.prod.baseURL"
    static let devApiKey = "folio.dev.apiKey"
    static let prodApiKey = "folio.prod.apiKey"
    static let apps = "folio.apps"
}

// MARK: - Environment

enum FolioEnvironment: String, CaseIterable, Identifiable {
    case dev
    case prod
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .dev: "Dev"
        case .prod: "Prod"
        }
    }
    
    var baseURLKey: String {
        switch self {
        case .dev: FolioStorageKey.devBaseURL
        case .prod: FolioStorageKey.prodBaseURL
        }
    }
    
    var apiKeyKey: String {
        switch self {
        case .dev: FolioStorageKey.devApiKey
        case .prod: FolioStorageKey.prodApiKey
        }
    }
}

// MARK: - Settings

/// The active environment's server settings, read fresh on every access so switching environments in Settings takes effect immediately.
struct ServerSettings {
    var userDefaults: UserDefaults = .standard
    var keychain: any KeychainStoring = KeychainService()
    
    var activeEnvironment: FolioEnvironment {
        userDefaults.string(forKey: FolioStorageKey.activeEnvironment).flatMap(FolioEnvironment.init(rawValue:)) ?? .dev
    }
    
    var baseURLString: String {
        userDefaults.string(forKey: activeEnvironment.baseURLKey) ?? ""
    }
    
    var apiKey: String {
        keychain.read(key: activeEnvironment.apiKeyKey) ?? ""
    }
}
