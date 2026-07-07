import Foundation

enum MediaType: String, Codable {
    case image
    case video
}

enum MediaContext: String, Codable {
    case projects
    case posts
}

struct MediaItem: Codable, Equatable, Identifiable {
    var id: String { url }
    var type: MediaType
    var url: String
    var caption: String?
}
