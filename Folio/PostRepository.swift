import Foundation

// MARK: - Partial update payload

struct PostUpdate: Encodable {
    var title: String?
    var excerpt: String?
    var content: String?
    var tags: [String]?
    var heroImage: String?
    var series: String?

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(excerpt, forKey: .excerpt)
        try c.encodeIfPresent(content, forKey: .content)
        try c.encodeIfPresent(tags, forKey: .tags)
        try c.encodeIfPresent(heroImage, forKey: .heroImage)
        try c.encodeIfPresent(series, forKey: .series)
    }

    enum CodingKeys: String, CodingKey {
        case title, excerpt, content, tags, heroImage, series
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
    private func processor() throws(APIError) -> URLProcessor {
        try .fromSettings()
    }

    private func postsURL(_ p: URLProcessor) -> URL {
        p.baseURL.appending(path: "api").appending(path: "posts")
    }

    func fetchPosts() async throws(APIError) -> [PostPreview] {
        let p = try processor()
        let data = try await p.get(postsURL(p))
        return try p.decode([PostPreview].self, from: data)
    }

    func fetchPostNavs() async throws(APIError) -> [PostNav] {
        let p = try processor()
        let url = postsURL(p).appending(path: "nav")
        let data = try await p.get(url)
        return try p.decode([PostNav].self, from: data)
    }

    func fetchPost(withId id: String) async throws(APIError) -> PostDetail {
        let p = try processor()
        let url = postsURL(p).appending(path: id)
        let data = try await p.get(url)
        return try p.decode(PostDetail.self, from: data)
    }

    func createPost(_ post: PostDetail) async throws(APIError) -> PostDetail {
        let p = try processor()
        let body = try p.encode(post)
        let data = try await p.post(postsURL(p), body: body)
        return try p.decode(PostDetail.self, from: data)
    }

    func updatePost(id: String, fields: PostUpdate) async throws(APIError) -> PostDetail {
        let p = try processor()
        let url = postsURL(p).appending(path: id)
        let body = try p.encode(fields)
        let data = try await p.put(url, body: body)
        return try p.decode(PostDetail.self, from: data)
    }

    func deletePost(id: String) async throws(APIError) {
        let p = try processor()
        try await p.delete(postsURL(p).appending(path: id))
    }
}
