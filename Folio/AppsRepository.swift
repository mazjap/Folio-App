import Foundation

// MARK: - Update payloads

/// The fields the privacy policy editor saves.
///
/// The server merges an update into the stored page, so a field left out keeps its old value. Every field is sent, and a `nil` `contactUrl` or `contactText` is sent as `null`, which clears it.
struct AppPrivacyPolicyUpdate: Encodable, Equatable {
    var appName: String
    var lastUpdated: String
    var content: String
    var contactUrl: String?
    var contactText: String?
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appName, forKey: .appName)
        try container.encode(lastUpdated, forKey: .lastUpdated)
        try container.encode(content, forKey: .content)
        try container.encode(contactUrl, forKey: .contactUrl)
        try container.encode(contactText, forKey: .contactText)
    }
    
    enum CodingKeys: String, CodingKey {
        case appName, lastUpdated, content, contactUrl, contactText
    }
}

/// The fields the support page editor saves. Like `AppPrivacyPolicyUpdate`, a `nil` contact field is sent as `null` to clear it.
struct AppSupportUpdate: Encodable, Equatable {
    var appName: String
    var version: String
    var subtitle: String
    var content: String
    var contactUrl: String?
    var contactText: String?
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appName, forKey: .appName)
        try container.encode(version, forKey: .version)
        try container.encode(subtitle, forKey: .subtitle)
        try container.encode(content, forKey: .content)
        try container.encode(contactUrl, forKey: .contactUrl)
        try container.encode(contactText, forKey: .contactText)
    }
    
    enum CodingKeys: String, CodingKey {
        case appName, version, subtitle, content, contactUrl, contactText
    }
}

// MARK: - Protocol

protocol AppsRepositoryProtocol {
    func fetchPrivacyPolicy(appId: String) async throws(APIError) -> AppPrivacyPolicy
    func createPrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy
    func updatePrivacyPolicy(appId: String, fields: AppPrivacyPolicyUpdate) async throws(APIError) -> AppPrivacyPolicy
    func deletePrivacyPolicy(appId: String) async throws(APIError)
    func fetchSupport(appId: String) async throws(APIError) -> AppSupport
    func createSupport(_ support: AppSupport) async throws(APIError) -> AppSupport
    func updateSupport(appId: String, fields: AppSupportUpdate) async throws(APIError) -> AppSupport
    func deleteSupport(appId: String) async throws(APIError)
}

// MARK: - Implementation

struct AppsRepository: AppsRepositoryProtocol {
    // MARK: - Privacy Policy
    
    func fetchPrivacyPolicy(appId: String) async throws(APIError) -> AppPrivacyPolicy {
        let p = try URLProcessor.fromSettings()
        let data = try await p.get(p.apiURL("apps", appId, "privacy-policy"))
        return try p.decode(AppPrivacyPolicy.self, from: data)
    }
    
    func createPrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy {
        let p = try URLProcessor.fromSettings()
        let data = try await p.post(p.apiURL("apps", policy.id, "privacy-policy"), body: try p.encode(policy))
        return try p.decode(AppPrivacyPolicy.self, from: data)
    }
    
    func updatePrivacyPolicy(appId: String, fields: AppPrivacyPolicyUpdate) async throws(APIError) -> AppPrivacyPolicy {
        let p = try URLProcessor.fromSettings()
        let data = try await p.put(p.apiURL("apps", appId, "privacy-policy"), body: try p.encode(fields))
        return try p.decode(AppPrivacyPolicy.self, from: data)
    }
    
    func deletePrivacyPolicy(appId: String) async throws(APIError) {
        let p = try URLProcessor.fromSettings()
        try await p.delete(p.apiURL("apps", appId, "privacy-policy"))
    }
    
    // MARK: - Support
    
    func fetchSupport(appId: String) async throws(APIError) -> AppSupport {
        let p = try URLProcessor.fromSettings()
        let data = try await p.get(p.apiURL("apps", appId, "support"))
        return try p.decode(AppSupport.self, from: data)
    }
    
    func createSupport(_ support: AppSupport) async throws(APIError) -> AppSupport {
        let p = try URLProcessor.fromSettings()
        let data = try await p.post(p.apiURL("apps", support.id, "support"), body: try p.encode(support))
        return try p.decode(AppSupport.self, from: data)
    }
    
    func updateSupport(appId: String, fields: AppSupportUpdate) async throws(APIError) -> AppSupport {
        let p = try URLProcessor.fromSettings()
        let data = try await p.put(p.apiURL("apps", appId, "support"), body: try p.encode(fields))
        return try p.decode(AppSupport.self, from: data)
    }
    
    func deleteSupport(appId: String) async throws(APIError) {
        let p = try URLProcessor.fromSettings()
        try await p.delete(p.apiURL("apps", appId, "support"))
    }
}

// MARK: - Test fake

/// Keeps app pages in memory and merges updates the way the server does, for tests and previews.
final class TestAppsRepository: AppsRepositoryProtocol {
    var privacyPolicies: [String: AppPrivacyPolicy]
    var supportPages: [String: AppSupport]
    /// When set, the fetches throw it.
    var fetchError: APIError?
    private(set) var privacyPolicyUpdates: [(appId: String, fields: AppPrivacyPolicyUpdate)] = []
    private(set) var supportUpdates: [(appId: String, fields: AppSupportUpdate)] = []
    
    init(privacyPolicies: [AppPrivacyPolicy] = [.sample], supportPages: [AppSupport] = [.sample]) {
        self.privacyPolicies = Dictionary(uniqueKeysWithValues: privacyPolicies.map { ($0.id, $0) })
        self.supportPages = Dictionary(uniqueKeysWithValues: supportPages.map { ($0.id, $0) })
    }
    
    func fetchPrivacyPolicy(appId: String) async throws(APIError) -> AppPrivacyPolicy {
        if let fetchError { throw fetchError }
        guard let policy = privacyPolicies[appId] else { throw .notFound }
        
        return policy
    }
    
    func createPrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy {
        guard privacyPolicies[policy.id] == nil else { throw .conflict }
        
        privacyPolicies[policy.id] = policy
        return policy
    }
    
    func updatePrivacyPolicy(appId: String, fields: AppPrivacyPolicyUpdate) async throws(APIError) -> AppPrivacyPolicy {
        guard var policy = privacyPolicies[appId] else { throw .notFound }
        
        privacyPolicyUpdates.append((appId, fields))
        policy.appName = fields.appName
        policy.lastUpdated = fields.lastUpdated
        policy.content = fields.content
        policy.contactUrl = fields.contactUrl
        policy.contactText = fields.contactText
        privacyPolicies[appId] = policy
        return policy
    }
    
    func deletePrivacyPolicy(appId: String) async throws(APIError) {
        guard privacyPolicies.removeValue(forKey: appId) != nil else { throw .notFound }
    }
    
    func fetchSupport(appId: String) async throws(APIError) -> AppSupport {
        if let fetchError { throw fetchError }
        guard let support = supportPages[appId] else { throw .notFound }
        
        return support
    }
    
    func createSupport(_ support: AppSupport) async throws(APIError) -> AppSupport {
        guard supportPages[support.id] == nil else { throw .conflict }
        
        supportPages[support.id] = support
        return support
    }
    
    func updateSupport(appId: String, fields: AppSupportUpdate) async throws(APIError) -> AppSupport {
        guard var support = supportPages[appId] else { throw .notFound }
        
        supportUpdates.append((appId, fields))
        support.appName = fields.appName
        support.version = fields.version
        support.subtitle = fields.subtitle
        support.content = fields.content
        support.contactUrl = fields.contactUrl
        support.contactText = fields.contactText
        supportPages[appId] = support
        return support
    }
    
    func deleteSupport(appId: String) async throws(APIError) {
        guard supportPages.removeValue(forKey: appId) != nil else { throw .notFound }
    }
}

extension AppPrivacyPolicy {
    static let sample = AppPrivacyPolicy(
        id: "sample-app",
        appName: "Sample App",
        lastUpdated: "2026-06-25",
        content: "## Data\n\nSample App doesn't collect any data.",
        contactUrl: nil,
        contactText: nil
    )
}

extension AppSupport {
    static let sample = AppSupport(
        id: "sample-app",
        appName: "Sample App",
        version: "1.0.0",
        subtitle: "Help with Sample App.",
        content: "## FAQ\n\nAsk away.",
        contactUrl: "https://example.com",
        contactText: "Contact Support"
    )
}
