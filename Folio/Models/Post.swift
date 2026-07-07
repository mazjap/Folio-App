import Foundation

struct PostPreview: Codable, Equatable {
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

    var nav: PostNav {
        PostNav(id: id, title: title, tags: tags, createdAt: createdAt, series: series)
    }
}

struct PostNav: Codable, Equatable {
  var id: String
  var title: String
  var tags: [String]
  var createdAt: Date
  var series: String?
}
