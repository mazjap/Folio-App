import Foundation

struct AppPrivacyPolicy: Codable, Identifiable, Equatable {
    var id: String
    var appName: String
    var lastUpdated: String   // "yyyy-MM-dd", set manually
    var content: String
    var contactUrl: String?
    var contactText: String?
}

struct AppSupport: Codable, Identifiable, Equatable {
    var id: String
    var appName: String
    var version: String
    var subtitle: String
    var content: String
    var contactUrl: String?
    var contactText: String?
}

struct AppRecord: Codable, Identifiable, Hashable {
    var id: String
}
