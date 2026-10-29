import Foundation

// MARK: - Storage keys

nonisolated enum FolioStorageKey {
    static let activeEnvironment = "folio.activeEnvironment"
    static let devBaseURL = "folio.dev.baseURL"
    static let prodBaseURL = "folio.prod.baseURL"
    static let devApiKey = "folio.dev.apiKey"
    static let prodApiKey = "folio.prod.apiKey"
    static let apps = "folio.apps"
}

// MARK: - Environment

nonisolated enum FolioEnvironment: String, CaseIterable, Identifiable {
    case dev
    case prod
    
    var id: Self { self }
    
    var title: String {
        switch self {
        case .dev: "Dev"
        case .prod: "Prod"
        }
    }
    
    var longTitle: String {
        switch self {
        case .dev: "Development"
        case .prod: "Production"
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
    
    /// The active environment's API key, or an empty string when none is saved.
    func apiKey() throws(KeychainService.KeychainError) -> String {
        try keychain.read(key: activeEnvironment.apiKeyKey) ?? ""
    }
}

// MARK: - Base URL

/// Checks a server's base URL as typed in Settings.
nonisolated enum ServerURL {
    enum Issue: Error, Equatable, LocalizedError {
        case empty
        case notAURL
        case unsupportedScheme
        case insecureHost
        case hasQueryOrFragment
        case includesAPIPath
        
        var errorDescription: String? {
            switch self {
            case .empty: "Enter the server's address."
            case .notAURL: "Enter a full address, like https://example.com."
            case .unsupportedScheme: "The address must start with https:// (or http:// for localhost)."
            case .insecureHost: "Only localhost can use http://. Use https:// for other servers."
            case .hasQueryOrFragment: "Remove the ? or # part of the address."
            case .includesAPIPath: "Enter the site's address without /api at the end. Folio adds it."
            }
        }
    }
    
    /// The URL with surrounding whitespace and trailing slashes removed, or why it can't be used. Only `localhost` can use plain HTTP, matching the app's transport security settings.
    static func normalize(_ string: String) -> Result<String, Issue> {
        var trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        
        guard let components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(), let host = components.host, !host.isEmpty else {
            return .failure(.notAURL)
        }
        guard scheme == "https" || scheme == "http" else { return .failure(.unsupportedScheme) }
        guard scheme == "https" || ["localhost", "127.0.0.1"].contains(host.lowercased()) else { return .failure(.insecureHost) }
        guard components.query == nil, components.fragment == nil else { return .failure(.hasQueryOrFragment) }
        guard !components.path.lowercased().hasSuffix("/api") else { return .failure(.includesAPIPath) }
        
        return .success(trimmed)
    }
}
