import Foundation

@Observable
class PostsViewModel {
    var posts: [PostPreview] = []
    var isLoading = false
    var error: APIError?

    private let repo = PostRepository()

    func fetchPosts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            posts = try await repo.fetchPosts()
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    func deletePost(id: String) async {
        do {
            try await repo.deletePost(id: id)
            posts.removeAll { $0.id == id }
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }

    func appendOrReplace(_ preview: PostPreview) {
        if let idx = posts.firstIndex(where: { $0.id == preview.id }) {
            posts[idx] = preview
        } else {
            posts.insert(preview, at: 0)
        }
    }
}
