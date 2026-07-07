import Foundation

// MARK: - Partial update payload

struct ProjectUpdate: Encodable {
    var title: String?
    var tagline: String?
    var description: String?
    var heroImage: String?
    var category: String?
    var status: ProjectStatus?
    var featured: Bool?
    var techStack: [String]?
    var links: [String: String]?
    var media: [MediaItem]?

    func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(tagline, forKey: .tagline)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(heroImage, forKey: .heroImage)
        try c.encodeIfPresent(category, forKey: .category)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encodeIfPresent(featured, forKey: .featured)
        try c.encodeIfPresent(techStack, forKey: .techStack)
        try c.encodeIfPresent(links, forKey: .links)
        try c.encodeIfPresent(media, forKey: .media)
    }

    enum CodingKeys: String, CodingKey {
        case title, tagline, description, heroImage, category, status, featured, techStack, links, media
    }
}

// MARK: - Protocol

protocol ProjectRepositoryProtocol {
    func fetchProjects() async throws(APIError) -> [ProjectPreview]
    func fetchProjectNavs() async throws(APIError) -> [ProjectNav]
    func fetchProject(withId id: String) async throws(APIError) -> ProjectDetail
    func createProject(_ project: ProjectDetail) async throws(APIError) -> ProjectDetail
    func updateProject(id: String, fields: ProjectUpdate) async throws(APIError) -> ProjectDetail
    func deleteProject(id: String) async throws(APIError)
}

// MARK: - Implementation

struct ProjectRepository: ProjectRepositoryProtocol {
    private func processor() throws(APIError) -> URLProcessor {
        try .fromSettings()
    }

    private func projectsURL(_ p: URLProcessor) -> URL {
        p.baseURL.appending(path: "api").appending(path: "projects")
    }

    func fetchProjects() async throws(APIError) -> [ProjectPreview] {
        let p = try processor()
        let data = try await p.get(projectsURL(p))
        return try p.decode([ProjectPreview].self, from: data)
    }

    func fetchProjectNavs() async throws(APIError) -> [ProjectNav] {
        let p = try processor()
        let url = projectsURL(p).appending(path: "nav")
        let data = try await p.get(url)
        return try p.decode([ProjectNav].self, from: data)
    }

    func fetchProject(withId id: String) async throws(APIError) -> ProjectDetail {
        let p = try processor()
        let url = projectsURL(p).appending(path: id)
        let data = try await p.get(url)
        return try p.decode(ProjectDetail.self, from: data)
    }

    func createProject(_ project: ProjectDetail) async throws(APIError) -> ProjectDetail {
        let p = try processor()
        let body = try p.encode(project)
        let data = try await p.post(projectsURL(p), body: body)
        return try p.decode(ProjectDetail.self, from: data)
    }

    func updateProject(id: String, fields: ProjectUpdate) async throws(APIError) -> ProjectDetail {
        let p = try processor()
        let url = projectsURL(p).appending(path: id)
        let body = try p.encode(fields)
        let data = try await p.put(url, body: body)
        return try p.decode(ProjectDetail.self, from: data)
    }

    func deleteProject(id: String) async throws(APIError) {
        let p = try processor()
        try await p.delete(projectsURL(p).appending(path: id))
    }
}
