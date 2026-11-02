import Foundation

struct PostPreview: Codable, Equatable, Identifiable {
    var id: String
    var title: String
    var excerpt: String
    var heroImage: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date?
    var readingTime: Int
    var series: String?
}

struct PostDetail: Codable, Equatable {
    var content: String
    var id: String
    var title: String
    var excerpt: String
    var heroImage: String?
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date?
    var readingTime: Int
    var series: String?
}

extension PostDetail {
    init(preview: PostPreview, content: String) {
        self.init(
            content: content,
            id: preview.id,
            title: preview.title,
            excerpt: preview.excerpt,
            heroImage: preview.heroImage,
            tags: preview.tags,
            createdAt: preview.createdAt,
            updatedAt: preview.updatedAt,
            readingTime: preview.readingTime,
            series: preview.series
        )
    }
    
    var preview: PostPreview {
        PostPreview(id: id, title: title, excerpt: excerpt, heroImage: heroImage, tags: tags, createdAt: createdAt, updatedAt: updatedAt, readingTime: readingTime, series: series)
    }
    
    /// The version the server compares a conditional save or delete with: when it was last updated, or created if it never was.
    var version: Date {
        updatedAt ?? createdAt
    }
}

extension PostPreview {
    /// Like `PostDetail.version`.
    var version: Date {
        updatedAt ?? createdAt
    }
}
