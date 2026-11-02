import Foundation

struct AppPrivacyPolicy: Codable, Identifiable, Equatable {
    var id: String
    var appName: String
    var lastUpdated: String   // "yyyy-MM-dd", set manually
    var content: String
    var contactUrl: String?
    var contactText: String?
    /// Set by the server on every save; `nil` for pages last saved before it did. It's the page's version for conditional saves.
    var updatedAt: Date?
}

struct AppSupport: Codable, Identifiable, Equatable {
    var id: String
    var appName: String
    var version: String
    var subtitle: String
    var content: String
    var contactUrl: String?
    var contactText: String?
    /// Set by the server on every save; `nil` for pages last saved before it did. It's the page's version for conditional saves.
    var updatedAt: Date?
}

/// The app pages a site has: `privacy-policy`, `support`, or both.
enum AppPageType: String, Codable {
    case privacyPolicy = "privacy-policy"
    case support
}

/// An entry of `GET /api/apps`.
struct AppSummary: Codable, Identifiable, Hashable {
    var id: String
    var appName: String
    var pages: [AppPageType]
}
