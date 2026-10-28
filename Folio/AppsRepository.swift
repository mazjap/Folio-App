import Foundation

class AppsRepository {

    // MARK: - Privacy Policy

    func fetchPrivacyPolicy(appId: String) async throws(APIError) -> AppPrivacyPolicy {
        let p = try URLProcessor.fromSettings()
        let data = try await p.get(p.baseURL.appendingPathComponent("api/apps/\(appId)/privacy-policy"))
        return try p.decode(AppPrivacyPolicy.self, from: data)
    }

    func createPrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy {
        let p = try URLProcessor.fromSettings()
        let data = try await p.post(
            p.baseURL.appendingPathComponent("api/apps/\(policy.id)/privacy-policy"),
            body: try p.encode(policy)
        )
        return try p.decode(AppPrivacyPolicy.self, from: data)
    }

    func updatePrivacyPolicy(_ policy: AppPrivacyPolicy) async throws(APIError) -> AppPrivacyPolicy {
        let p = try URLProcessor.fromSettings()
        let data = try await p.put(
            p.baseURL.appendingPathComponent("api/apps/\(policy.id)/privacy-policy"),
            body: try p.encode(policy)
        )
        return try p.decode(AppPrivacyPolicy.self, from: data)
    }

    func deletePrivacyPolicy(appId: String) async throws(APIError) {
        let p = try URLProcessor.fromSettings()
        try await p.delete(p.baseURL.appendingPathComponent("api/apps/\(appId)/privacy-policy"))
    }

    // MARK: - Support

    func fetchSupport(appId: String) async throws(APIError) -> AppSupport {
        let p = try URLProcessor.fromSettings()
        let data = try await p.get(p.baseURL.appendingPathComponent("api/apps/\(appId)/support"))
        return try p.decode(AppSupport.self, from: data)
    }

    func createSupport(_ support: AppSupport) async throws(APIError) -> AppSupport {
        let p = try URLProcessor.fromSettings()
        let data = try await p.post(
            p.baseURL.appendingPathComponent("api/apps/\(support.id)/support"),
            body: try p.encode(support)
        )
        return try p.decode(AppSupport.self, from: data)
    }

    func updateSupport(_ support: AppSupport) async throws(APIError) -> AppSupport {
        let p = try URLProcessor.fromSettings()
        let data = try await p.put(
            p.baseURL.appendingPathComponent("api/apps/\(support.id)/support"),
            body: try p.encode(support)
        )
        return try p.decode(AppSupport.self, from: data)
    }

    func deleteSupport(appId: String) async throws(APIError) {
        let p = try URLProcessor.fromSettings()
        try await p.delete(p.baseURL.appendingPathComponent("api/apps/\(appId)/support"))
    }
}
