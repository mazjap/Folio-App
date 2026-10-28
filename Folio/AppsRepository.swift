import Foundation

// MARK: - Protocol

protocol AppsRepositoryProtocol {
    func fetchPrivacyPolicy(appId: String) async throws(APIError) -> AppPrivacyPolicy
    func createPrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy
    func updatePrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy
    func deletePrivacyPolicy(appId: String) async throws(APIError)
    func fetchSupport(appId: String) async throws(APIError) -> AppSupport
    func createSupport(_ support: AppSupport) async throws(APIError) -> AppSupport
    func updateSupport(_ support: AppSupport) async throws(APIError) -> AppSupport
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
    
    func updatePrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy {
        let p = try URLProcessor.fromSettings()
        let data = try await p.put(p.apiURL("apps", policy.id, "privacy-policy"), body: try p.encode(policy))
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
    
    func updateSupport(_ support: AppSupport) async throws(APIError) -> AppSupport {
        let p = try URLProcessor.fromSettings()
        let data = try await p.put(p.apiURL("apps", support.id, "support"), body: try p.encode(support))
        return try p.decode(AppSupport.self, from: data)
    }
    
    func deleteSupport(appId: String) async throws(APIError) {
        let p = try URLProcessor.fromSettings()
        try await p.delete(p.apiURL("apps", appId, "support"))
    }
}

// MARK: - Test fake

/// Keeps app pages in memory, for tests and previews.
final class TestAppsRepository: AppsRepositoryProtocol {
    var privacyPolicies: [String: AppPrivacyPolicy]
    var supportPages: [String: AppSupport]
    
    init(privacyPolicies: [AppPrivacyPolicy] = [.sample], supportPages: [AppSupport] = [.sample]) {
        self.privacyPolicies = Dictionary(uniqueKeysWithValues: privacyPolicies.map { ($0.id, $0) })
        self.supportPages = Dictionary(uniqueKeysWithValues: supportPages.map { ($0.id, $0) })
    }
    
    func fetchPrivacyPolicy(appId: String) async throws(APIError) -> AppPrivacyPolicy {
        guard let policy = privacyPolicies[appId] else { throw .notFound }
        
        return policy
    }
    
    func createPrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy {
        guard privacyPolicies[policy.id] == nil else { throw .conflict }
        
        privacyPolicies[policy.id] = policy
        return policy
    }
    
    func updatePrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy {
        guard privacyPolicies[policy.id] != nil else { throw .notFound }
        
        privacyPolicies[policy.id] = policy
        return policy
    }
    
    func deletePrivacyPolicy(appId: String) async throws(APIError) {
        guard privacyPolicies.removeValue(forKey: appId) != nil else { throw .notFound }
    }
    
    func fetchSupport(appId: String) async throws(APIError) -> AppSupport {
        guard let support = supportPages[appId] else { throw .notFound }
        
        return support
    }
    
    func createSupport(_ support: AppSupport) async throws(APIError) -> AppSupport {
        guard supportPages[support.id] == nil else { throw .conflict }
        
        supportPages[support.id] = support
        return support
    }
    
    func updateSupport(_ support: AppSupport) async throws(APIError) -> AppSupport {
        guard supportPages[support.id] != nil else { throw .notFound }
        
        supportPages[support.id] = support
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
