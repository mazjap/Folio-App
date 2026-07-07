import Foundation

@Observable
class ProjectsViewModel {
    var projects: [ProjectPreview] = []
    var isLoading = false
    var error: APIError?

    private let repo = ProjectRepository()

    func fetchProjects() async {
        isLoading = true
        defer { isLoading = false }
        do {
            projects = try await repo.fetchProjects()
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    func deleteProject(id: String) async {
        do {
            try await repo.deleteProject(id: id)
            projects.removeAll { $0.id == id }
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    func appendOrReplace(_ preview: ProjectPreview) {
        if let idx = projects.firstIndex(where: { $0.id == preview.id }) {
            projects[idx] = preview
        } else {
            projects.insert(preview, at: 0)
        }
    }
}
