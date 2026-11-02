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
    /// Every app with at least one page on the server.
    func fetchApps() async throws(APIError) -> [AppSummary]
    func fetchPrivacyPolicy(appId: String) async throws(APIError) -> AppPrivacyPolicy
    func createPrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy
    /// - Parameter expectedVersion: The `updatedAt` of the page the edit started from; the server refuses the save (`APIError.versionConflict`) if it changed since. `nil` for pages without one saves unconditionally.
    func updatePrivacyPolicy(appId: String, fields: AppPrivacyPolicyUpdate, expectedVersion: Date?) async throws(APIError) -> AppPrivacyPolicy
    func deletePrivacyPolicy(appId: String, expectedVersion: Date?) async throws(APIError)
    func fetchSupport(appId: String) async throws(APIError) -> AppSupport
    func createSupport(_ support: AppSupport) async throws(APIError) -> AppSupport
    /// - Parameter expectedVersion: Like `updatePrivacyPolicy`'s.
    func updateSupport(appId: String, fields: AppSupportUpdate, expectedVersion: Date?) async throws(APIError) -> AppSupport
    func deleteSupport(appId: String, expectedVersion: Date?) async throws(APIError)
}

// MARK: - Implementation

struct AppsRepository: AppsRepositoryProtocol {
    func fetchApps() async throws(APIError) -> [AppSummary] {
        let p = try URLProcessor.fromSettings()
        let data = try await p.get(p.apiURL("apps"))
        return try p.decode([AppSummary].self, from: data)
    }
    
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
    
    func updatePrivacyPolicy(appId: String, fields: AppPrivacyPolicyUpdate, expectedVersion: Date?) async throws(APIError) -> AppPrivacyPolicy {
        let p = try URLProcessor.fromSettings()
        let data = try await p.put(p.apiURL("apps", appId, "privacy-policy"), body: try p.encode(fields), expectedVersion: expectedVersion)
        return try p.decode(AppPrivacyPolicy.self, from: data)
    }
    
    func deletePrivacyPolicy(appId: String, expectedVersion: Date?) async throws(APIError) {
        let p = try URLProcessor.fromSettings()
        try await p.delete(p.apiURL("apps", appId, "privacy-policy"), expectedVersion: expectedVersion)
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
    
    func updateSupport(appId: String, fields: AppSupportUpdate, expectedVersion: Date?) async throws(APIError) -> AppSupport {
        let p = try URLProcessor.fromSettings()
        let data = try await p.put(p.apiURL("apps", appId, "support"), body: try p.encode(fields), expectedVersion: expectedVersion)
        return try p.decode(AppSupport.self, from: data)
    }
    
    func deleteSupport(appId: String, expectedVersion: Date?) async throws(APIError) {
        let p = try URLProcessor.fromSettings()
        try await p.delete(p.apiURL("apps", appId, "support"), expectedVersion: expectedVersion)
    }
}

// MARK: - Test fake

/// Keeps app pages in memory and handles writes the way the server does (merging updates, setting `updatedAt`, refusing writes based on an old version), for tests and previews.
final class TestAppsRepository: AppsRepositoryProtocol {
    var privacyPolicies: [String: AppPrivacyPolicy]
    var supportPages: [String: AppSupport]
    /// When set, the fetches throw it.
    var fetchError: APIError?
    /// When set, `fetchApps()` throws it.
    var listError: APIError?
    /// The `updatedAt` the "server" gives a saved page.
    var updateDate = Date.sampleDate.addingTimeInterval(3600)
    /// The `expectedVersion` of each update and delete, in order.
    private(set) var expectedVersions: [Date?] = []
    private(set) var privacyPolicyUpdates: [(appId: String, fields: AppPrivacyPolicyUpdate)] = []
    private(set) var supportUpdates: [(appId: String, fields: AppSupportUpdate)] = []
    
    init(privacyPolicies: [AppPrivacyPolicy] = [.sample], supportPages: [AppSupport] = [.sample]) {
        self.privacyPolicies = Dictionary(uniqueKeysWithValues: privacyPolicies.map { ($0.id, $0) })
        self.supportPages = Dictionary(uniqueKeysWithValues: supportPages.map { ($0.id, $0) })
    }
    
    func fetchApps() async throws(APIError) -> [AppSummary] {
        if let listError { throw listError }
        
        return Set(privacyPolicies.keys).union(supportPages.keys).sorted().map { id in
            let pages: [AppPageType] = (privacyPolicies[id] == nil ? [] : [.privacyPolicy]) + (supportPages[id] == nil ? [] : [.support])
            return AppSummary(id: id, appName: privacyPolicies[id]?.appName ?? supportPages[id]?.appName ?? id, pages: pages)
        }
    }
    
    func fetchPrivacyPolicy(appId: String) async throws(APIError) -> AppPrivacyPolicy {
        if let fetchError { throw fetchError }
        guard let policy = privacyPolicies[appId] else { throw .notFound }
        
        return policy
    }
    
    func createPrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy {
        guard privacyPolicies[policy.id] == nil else { throw .conflict(message: "Privacy policy already exists") }
        
        var stored = policy
        stored.updatedAt = updateDate
        privacyPolicies[policy.id] = stored
        return stored
    }
    
    func updatePrivacyPolicy(appId: String, fields: AppPrivacyPolicyUpdate, expectedVersion: Date?) async throws(APIError) -> AppPrivacyPolicy {
        guard var policy = privacyPolicies[appId] else { throw .notFound }
        
        try checkVersion(expectedVersion, current: policy.updatedAt, label: "privacy policy")
        privacyPolicyUpdates.append((appId, fields))
        policy.appName = fields.appName
        policy.lastUpdated = fields.lastUpdated
        policy.content = fields.content
        policy.contactUrl = fields.contactUrl
        policy.contactText = fields.contactText
        policy.updatedAt = updateDate
        privacyPolicies[appId] = policy
        return policy
    }
    
    func deletePrivacyPolicy(appId: String, expectedVersion: Date?) async throws(APIError) {
        guard let policy = privacyPolicies[appId] else { throw .notFound }
        
        try checkVersion(expectedVersion, current: policy.updatedAt, label: "privacy policy")
        privacyPolicies[appId] = nil
    }
    
    func fetchSupport(appId: String) async throws(APIError) -> AppSupport {
        if let fetchError { throw fetchError }
        guard let support = supportPages[appId] else { throw .notFound }
        
        return support
    }
    
    func createSupport(_ support: AppSupport) async throws(APIError) -> AppSupport {
        guard supportPages[support.id] == nil else { throw .conflict(message: "Support page already exists") }
        
        var stored = support
        stored.updatedAt = updateDate
        supportPages[support.id] = stored
        return stored
    }
    
    func updateSupport(appId: String, fields: AppSupportUpdate, expectedVersion: Date?) async throws(APIError) -> AppSupport {
        guard var support = supportPages[appId] else { throw .notFound }
        
        try checkVersion(expectedVersion, current: support.updatedAt, label: "support page")
        supportUpdates.append((appId, fields))
        support.appName = fields.appName
        support.version = fields.version
        support.subtitle = fields.subtitle
        support.content = fields.content
        support.contactUrl = fields.contactUrl
        support.contactText = fields.contactText
        support.updatedAt = updateDate
        supportPages[appId] = support
        return support
    }
    
    func deleteSupport(appId: String, expectedVersion: Date?) async throws(APIError) {
        guard let support = supportPages[appId] else { throw .notFound }
        
        try checkVersion(expectedVersion, current: support.updatedAt, label: "support page")
        supportPages[appId] = nil
    }
    
    /// Refuses a write based on an older version, like the server: a page without a version counts as changed when one is sent.
    private func checkVersion(_ expected: Date?, current: Date?, label: String) throws(APIError) {
        expectedVersions.append(expected)
        guard let expected else { return }
        
        guard let current, expected.isSameVersion(as: current) else {
            throw .versionConflict(message: "This \(label) was changed on the server after you opened it.")
        }
    }
}

extension AppPrivacyPolicy {
    static let sample = AppPrivacyPolicy(
        id: "sample-app",
        appName: "Sample App",
        lastUpdated: "2026-06-25",
        content: "## Data\n\nSample App doesn't collect any data.",
        contactUrl: nil,
        contactText: nil,
        updatedAt: .sampleDate
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
        contactText: "Contact Support",
        updatedAt: .sampleDate
    )
}
