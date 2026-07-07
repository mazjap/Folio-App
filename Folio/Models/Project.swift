import Foundation

enum ProjectStatus: String, Codable {
    case active
    case inProgress = "in-progress"
    case archived
}

struct ProjectPreview: Codable, Equatable {
    var id: String
    var title: String
    var tagline: String
    var heroImage: String
    var category: String?
    var status: ProjectStatus
    var featured: Bool
    var createdAt: Date
    var updatedAt: Date?
}

struct ProjectDetail: Codable, Equatable {
    var id: String
    var title: String
    var tagline: String
    var heroImage: String
    var category: String?
    var status: ProjectStatus
    var featured: Bool
    var createdAt: Date
    var updatedAt: Date?
    var description: String
    var media: [MediaItem]
    var techStack: [String]
    var links: [String : String]
}

extension ProjectDetail {
    init(preview: ProjectPreview, description: String, media: [MediaItem], techStack: [String], links: [String: String]) {
        self.init(
            id: preview.id,
            title: preview.title,
            tagline: preview.tagline,
            heroImage: preview.heroImage,
            category: preview.category,
            status: preview.status,
            featured: preview.featured,
            createdAt: preview.createdAt,
            updatedAt: preview.updatedAt,
            description: description,
            media: media,
            techStack: techStack,
            links: links
        )
    }

    var preview: ProjectPreview {
        ProjectPreview(id: id, title: title, tagline: tagline, heroImage: heroImage, category: category, status: status, featured: featured, createdAt: createdAt, updatedAt: updatedAt)
    }

    var nav: ProjectNav {
        ProjectNav(id: id, title: title, status: status)
    }
}

struct ProjectNav: Codable, Equatable {
    var id: String
    var title: String
    var status: ProjectStatus
}
