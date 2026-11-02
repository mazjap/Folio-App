import Foundation

// MARK: - Update payload

/// The fields the project editor saves.
///
/// The server merges an update into the stored project, so a field left out keeps its old value. Every field is sent: an empty `heroImage` clears it, and a `nil` `category` is sent as `null`, which clears it. Only `createdAt` is left out when `nil`.
struct ProjectUpdate: Encodable, Equatable {
    var title: String
    var tagline: String
    var description: String
    var heroImage: String
    var category: String?
    var status: ProjectStatus
    var featured: Bool
    var techStack: [String]
    var links: [String: String]
    var media: [MediaItem]
    var createdAt: Date?
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(title, forKey: .title)
        try container.encode(tagline, forKey: .tagline)
        try container.encode(description, forKey: .description)
        try container.encode(heroImage, forKey: .heroImage)
        try container.encode(category, forKey: .category)
        try container.encode(status, forKey: .status)
        try container.encode(featured, forKey: .featured)
        try container.encode(techStack, forKey: .techStack)
        try container.encode(links, forKey: .links)
        try container.encode(media, forKey: .media)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
    }
    
    enum CodingKeys: String, CodingKey {
        case title, tagline, description, heroImage, category, status, featured, techStack, links, media, createdAt
    }
}

// MARK: - Protocol

protocol ProjectRepositoryProtocol {
    func fetchProjects() async throws(APIError) -> [ProjectPreview]
    func fetchProject(withId id: String) async throws(APIError) -> ProjectDetail
    func createProject(_ project: ProjectDetail) async throws(APIError) -> ProjectDetail
    /// - Parameter expectedVersion: The `version` of the project the edit started from; the server refuses the save (`APIError.versionConflict`) if it changed since.
    func updateProject(id: String, fields: ProjectUpdate, expectedVersion: Date?) async throws(APIError) -> ProjectDetail
    /// - Parameter expectedVersion: The `version` of the project being deleted; the server refuses if it changed since.
    func deleteProject(id: String, expectedVersion: Date?) async throws(APIError)
}

// MARK: - Implementation

struct ProjectRepository: ProjectRepositoryProtocol {
    func fetchProjects() async throws(APIError) -> [ProjectPreview] {
        let p = try URLProcessor.fromSettings()
        let data = try await p.get(p.apiURL("projects"))
        return try p.decode([ProjectPreview].self, from: data)
    }
    
    func fetchProject(withId id: String) async throws(APIError) -> ProjectDetail {
        let p = try URLProcessor.fromSettings()
        let data = try await p.get(p.apiURL("projects", id))
        return try p.decode(ProjectDetail.self, from: data)
    }
    
    func createProject(_ project: ProjectDetail) async throws(APIError) -> ProjectDetail {
        let p = try URLProcessor.fromSettings()
        let data = try await p.post(p.apiURL("projects"), body: try p.encode(project))
        return try p.decode(ProjectDetail.self, from: data)
    }
    
    func updateProject(id: String, fields: ProjectUpdate, expectedVersion: Date?) async throws(APIError) -> ProjectDetail {
        let p = try URLProcessor.fromSettings()
        let data = try await p.put(p.apiURL("projects", id), body: try p.encode(fields), expectedVersion: expectedVersion)
        return try p.decode(ProjectDetail.self, from: data)
    }
    
    func deleteProject(id: String, expectedVersion: Date?) async throws(APIError) {
        let p = try URLProcessor.fromSettings()
        try await p.delete(p.apiURL("projects", id), expectedVersion: expectedVersion)
    }
}

// MARK: - Test fake

/// Keeps projects in memory and handles writes the way the server does (merging updates, refusing writes based on an old version), for tests and previews.
final class TestProjectRepository: ProjectRepositoryProtocol {
    var projects: [ProjectDetail]
    /// When set, `fetchProject(withId:)` throws it.
    var fetchError: APIError?
    /// The `updatedAt` the "server" gives an updated project.
    var updateDate = Date.sampleDate.addingTimeInterval(3600)
    private(set) var updates: [(id: String, fields: ProjectUpdate)] = []
    /// The `expectedVersion` of each update and delete, in order.
    private(set) var expectedVersions: [Date?] = []
    private(set) var deletedIDs: [String] = []
    
    init(projects: [ProjectDetail] = [.sample]) {
        self.projects = projects
    }
    
    func fetchProjects() async throws(APIError) -> [ProjectPreview] {
        projects.map(\.preview)
    }
    
    func fetchProject(withId id: String) async throws(APIError) -> ProjectDetail {
        if let fetchError { throw fetchError }
        guard let project = projects.first(where: { $0.id == id }) else { throw .notFound }
        
        return project
    }
    
    func createProject(_ project: ProjectDetail) async throws(APIError) -> ProjectDetail {
        guard !projects.contains(where: { $0.id == project.id }) else { throw .conflict(message: "Project already exists") }
        
        var stored = project
        stored.updatedAt = nil
        projects.append(stored)
        return stored
    }
    
    func updateProject(id: String, fields: ProjectUpdate, expectedVersion: Date?) async throws(APIError) -> ProjectDetail {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { throw .notFound }
        
        expectedVersions.append(expectedVersion)
        if let expectedVersion, !expectedVersion.isSameVersion(as: projects[index].version) {
            throw .versionConflict(message: "This project was changed on the server after you opened it.")
        }
        updates.append((id, fields))
        projects[index].title = fields.title
        projects[index].tagline = fields.tagline
        projects[index].description = fields.description
        projects[index].heroImage = fields.heroImage
        projects[index].category = fields.category
        projects[index].status = fields.status
        projects[index].featured = fields.featured
        projects[index].techStack = fields.techStack
        projects[index].links = fields.links
        projects[index].media = fields.media
        projects[index].createdAt = fields.createdAt ?? projects[index].createdAt
        projects[index].updatedAt = updateDate
        return projects[index]
    }
    
    func deleteProject(id: String, expectedVersion: Date?) async throws(APIError) {
        guard let project = projects.first(where: { $0.id == id }) else { throw .notFound }
        
        expectedVersions.append(expectedVersion)
        if let expectedVersion, !expectedVersion.isSameVersion(as: project.version) {
            throw .versionConflict(message: "This project was changed on the server after you opened it.")
        }
        projects.removeAll { $0.id == id }
        deletedIDs.append(id)
    }
}

extension ProjectDetail {
    static let sample = ProjectDetail(
        id: "sample-project",
        title: "Sample Project",
        tagline: "A project for previews and tests.",
        heroImage: "/media/projects/sample-project/hero.webp",
        category: "iOS App",
        status: .active,
        featured: true,
        createdAt: .sampleDate,
        updatedAt: .sampleDate,
        description: "Built with **SwiftUI**.",
        media: [
            MediaItem(type: .image, url: "/media/projects/sample-project/one.webp", caption: "First"),
            MediaItem(type: .image, url: "/media/projects/sample-project/two.webp", caption: nil)
        ],
        techStack: ["Swift", "SwiftUI"],
        links: ["GitHub": "https://github.com"]
    )
}
