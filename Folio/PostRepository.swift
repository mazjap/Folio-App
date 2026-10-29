import Foundation

// MARK: - Update payload

/// The fields the post editor saves.
///
/// The server merges an update into the stored post, so a field left out keeps its old value. Every field is sent, and a `nil` `heroImage` or `series` is sent as `null`, which clears it. Only `createdAt` is left out when `nil`.
struct PostUpdate: Encodable, Equatable {
    var title: String
    var excerpt: String
    var content: String
    var tags: [String]
    var heroImage: String?
    var series: String?
    var createdAt: Date?
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(excerpt, forKey: .excerpt)
        try container.encode(content, forKey: .content)
        try container.encode(tags, forKey: .tags)
        try container.encode(heroImage, forKey: .heroImage)
        try container.encode(series, forKey: .series)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
    
    enum CodingKeys: String, CodingKey {
        case title, excerpt, content, tags, heroImage, series, createdAt
    }
}

// MARK: - Protocol

protocol PostRepositoryProtocol {
    func fetchPosts() async throws(APIError) -> [PostPreview]
    func fetchPostNavs() async throws(APIError) -> [PostNav]
    func fetchPost(withId id: String) async throws(APIError) -> PostDetail
    func createPost(_ post: PostDetail) async throws(APIError) -> PostDetail
    func updatePost(id: String, fields: PostUpdate) async throws(APIError) -> PostDetail
    func deletePost(id: String) async throws(APIError)
}

// MARK: - Implementation

struct PostRepository: PostRepositoryProtocol {
    func fetchPosts() async throws(APIError) -> [PostPreview] {
        let p = try URLProcessor.fromSettings()
        let data = try await p.get(p.apiURL("posts"))
        return try p.decode([PostPreview].self, from: data)
    }
    
    func fetchPostNavs() async throws(APIError) -> [PostNav] {
        let p = try URLProcessor.fromSettings()
        let data = try await p.get(p.apiURL("posts", "nav"))
        return try p.decode([PostNav].self, from: data)
    }
    
    func fetchPost(withId id: String) async throws(APIError) -> PostDetail {
        let p = try URLProcessor.fromSettings()
        let data = try await p.get(p.apiURL("posts", id))
        return try p.decode(PostDetail.self, from: data)
    }
    
    func createPost(_ post: PostDetail) async throws(APIError) -> PostDetail {
        let p = try URLProcessor.fromSettings()
        let data = try await p.post(p.apiURL("posts"), body: try p.encode(post))
        return try p.decode(PostDetail.self, from: data)
    }
    
    func updatePost(id: String, fields: PostUpdate) async throws(APIError) -> PostDetail {
        let p = try URLProcessor.fromSettings()
        let data = try await p.put(p.apiURL("posts", id), body: try p.encode(fields))
        return try p.decode(PostDetail.self, from: data)
    }
    
    func deletePost(id: String) async throws(APIError) {
        let p = try URLProcessor.fromSettings()
        try await p.delete(p.apiURL("posts", id))
    }
}

// MARK: - Test fake

/// Keeps posts in memory and merges updates the way the server does, for tests and previews.
final class TestPostRepository: PostRepositoryProtocol {
    var posts: [PostDetail]
    /// When set, `fetchPost(withId:)` throws it.
    var fetchError: APIError?
    /// When set, `fetchPosts()` throws it.
    var listError: APIError?
    /// Runs before `fetchPosts()` returns, so a test can hold a load open.
    var beforeList: (() async -> Void)?
    /// Runs before a create or update is applied, so a test can act while a save is in flight.
    var beforeWrite: (() async -> Void)?
    /// The `updatedAt` the "server" gives an updated post.
    var updateDate = Date.sampleDate.addingTimeInterval(3600)
    private(set) var updates: [(id: String, fields: PostUpdate)] = []
    private(set) var deletedIDs: [String] = []
    
    init(posts: [PostDetail] = [.sample]) {
        self.posts = posts
    }
    
    func fetchPosts() async throws(APIError) -> [PostPreview] {
        let result = posts.map(\.preview)
        await beforeList?()
        if let listError { throw listError }
        
        return result
    }
    
    func fetchPostNavs() async throws(APIError) -> [PostNav] {
        posts.map(\.nav)
    }
    
    func fetchPost(withId id: String) async throws(APIError) -> PostDetail {
        if let fetchError { throw fetchError }
        guard let post = posts.first(where: { $0.id == id }) else { throw .notFound }
        
        return post
    }
    
    func createPost(_ post: PostDetail) async throws(APIError) -> PostDetail {
        await beforeWrite?()
        guard !posts.contains(where: { $0.id == post.id }) else { throw .conflict }
        
        posts.append(post)
        return post
    }
    
    func updatePost(id: String, fields: PostUpdate) async throws(APIError) -> PostDetail {
        await beforeWrite?()
        guard let index = posts.firstIndex(where: { $0.id == id }) else { throw .notFound }
        
        updates.append((id, fields))
        posts[index].title = fields.title
        posts[index].excerpt = fields.excerpt
        posts[index].content = fields.content
        posts[index].tags = fields.tags
        posts[index].heroImage = fields.heroImage
        posts[index].series = fields.series
        posts[index].createdAt = fields.createdAt ?? posts[index].createdAt
        posts[index].updatedAt = updateDate
        return posts[index]
    }
    
    func deletePost(id: String) async throws(APIError) {
        guard posts.contains(where: { $0.id == id }) else { throw .notFound }
        
        posts.removeAll { $0.id == id }
        deletedIDs.append(id)
    }
}

extension PostDetail {
    static let sample = PostDetail(
        content: "# Hello\n\nThis is a sample post.\n\n![](/media/posts/sample-post/inline.webp)",
        id: "sample-post",
        title: "Sample Post",
        excerpt: "A post for previews and tests.",
        heroImage: "/media/posts/sample-post/hero.webp",
        tags: ["swift", "swiftui"],
        createdAt: .sampleDate,
        updatedAt: .sampleDate,
        readingTime: 1,
        series: "Samples"
    )
}
