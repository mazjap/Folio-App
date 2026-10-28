import Foundation

/// The list behind the Posts and Projects tabs: the items, which one is open, and whether a new one is being created.
@Observable
class ContentListViewModel<Item: Identifiable & Equatable> where Item.ID == String {
    var items: [Item] = []
    var isLoading = false
    var error: APIError?
    
    /// The item open in the editor.
    var selectedID: String?
    
    /// Whether the editor for a new item is open.
    var isCreatingNew = false
    
    @ObservationIgnored private let fetchItems: () async throws(APIError) -> [Item]
    @ObservationIgnored private let deleteItem: (String) async throws(APIError) -> Void
    @ObservationIgnored private var hasLoaded = false
    
    init(
        fetch: @escaping () async throws(APIError) -> [Item],
        delete: @escaping (String) async throws(APIError) -> Void
    ) {
        self.fetchItems = fetch
        self.deleteItem = delete
    }
    
    // MARK: - Functions
    
    /// Loads the items the first time the list appears.
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        
        hasLoaded = true
        await refresh()
    }
    
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            items = try await fetchItems()
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
    
    func delete(id: String) async {
        do {
            try await deleteItem(id)
            remove(id: id)
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
    
    /// Opens the editor for a new item.
    func startCreating() {
        // NOTE: - The selection must be cleared first. With both navigation destinations active, SwiftUI shows the selected item's editor instead of the new one.
        selectedID = nil
        isCreatingNew = true
    }
    
    /// Closes the editor and forgets the selection, so returning to the tab doesn't reopen it.
    func clearSelection() {
        selectedID = nil
        isCreatingNew = false
    }
    
    /// Shows a saved item: updated in place if it's in the list, or added to the top if it's new.
    func appendOrReplace(_ item: Item) {
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
    }
    
    func remove(id: String) {
        items.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
    }
}

// MARK: - Posts

typealias PostsViewModel = ContentListViewModel<PostPreview>

extension ContentListViewModel where Item == PostPreview {
    /// - Parameter drafts: Where editors save drafts. A deleted post's draft is deleted with it.
    convenience init(repo: any PostRepositoryProtocol = PostRepository(), drafts: DraftStore = .live) {
        self.init(
            fetch: { () async throws(APIError) -> [PostPreview] in
                try await repo.fetchPosts()
            },
            delete: { (id: String) async throws(APIError) in
                try await repo.deletePost(id: id)
                drafts.clear(key: PostEditorViewModel.draftKey(for: .edit(id: id)))
            }
        )
    }
}

// MARK: - Projects

typealias ProjectsViewModel = ContentListViewModel<ProjectPreview>

extension ContentListViewModel where Item == ProjectPreview {
    /// - Parameter drafts: Where editors save drafts. A deleted project's draft is deleted with it.
    convenience init(repo: any ProjectRepositoryProtocol = ProjectRepository(), drafts: DraftStore = .live) {
        self.init(
            fetch: { () async throws(APIError) -> [ProjectPreview] in
                try await repo.fetchProjects()
            },
            delete: { (id: String) async throws(APIError) in
                try await repo.deleteProject(id: id)
                drafts.clear(key: ProjectFormViewModel.draftKey(for: .edit(id: id)))
            }
        )
    }
}
