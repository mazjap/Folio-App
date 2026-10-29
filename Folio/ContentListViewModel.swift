import Foundation

/// The list behind the Posts and Projects tabs: the items, which one is open, and whether a new one is being created.
@Observable
class ContentListViewModel<Item: Identifiable & Equatable> where Item.ID == String {
    var items: [Item] = []
    var isLoading = false
    var error: APIError?
    
    /// Why the list couldn't load, shown in place of the empty list. Errors refreshing a list that has items are shown in an alert instead.
    private(set) var loadError: APIError?
    
    /// Whether a load has finished, so an empty list isn't described as empty before it's loaded.
    private(set) var hasFinishedLoading = false
    
    /// The environment the items were loaded from. Deleting only goes to its server.
    private(set) var loadedEnvironment: FolioEnvironment?
    
    /// The item open in the editor.
    var selectedID: String?
    
    /// Whether the editor for a new item is open.
    var isCreatingNew = false
    
    /// The item waiting for the user to confirm deleting it.
    var pendingDeletion: Item?
    
    @ObservationIgnored private let fetchItems: () async throws(APIError) -> [Item]
    @ObservationIgnored private let deleteItem: (String, FolioEnvironment) async throws(APIError) -> Void
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var hasLoaded = false
    
    /// Counts loads and local changes, so a slower, older load can't replace newer items.
    @ObservationIgnored private var generation = 0
    
    init(
        userDefaults: UserDefaults = .standard,
        fetch: @escaping () async throws(APIError) -> [Item],
        delete: @escaping (String, FolioEnvironment) async throws(APIError) -> Void
    ) {
        self.userDefaults = userDefaults
        self.fetchItems = fetch
        self.deleteItem = delete
    }
    
    // MARK: - Computed Properties
    
    var activeEnvironment: FolioEnvironment {
        ServerSettings(userDefaults: userDefaults).activeEnvironment
    }
    
    // MARK: - Functions
    
    /// Loads the items the first time the list appears, and again if that load was cancelled.
    func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        
        await refresh()
    }
    
    func refresh() async {
        generation += 1
        let thisLoad = generation
        let environment = activeEnvironment
        isLoading = true
        
        let result: Result<[Item], APIError>
        do {
            result = .success(try await fetchItems())
        } catch {
            result = .failure(error)
        }
        
        // NOTE: - A newer load or a local change superseded this one, so its results are out of date.
        guard thisLoad == generation else { return }
        
        isLoading = false
        switch result {
        case let .success(fetched):
            items = fetched
            loadError = nil
            loadedEnvironment = environment
            hasLoaded = true
        case let .failure(error):
            // NOTE: - A cancelled first load (like switching tabs before it finished) is tried again the next time the list appears.
            guard !error.isCancellation else { return }
            
            hasLoaded = true
            if items.isEmpty {
                loadError = error
            } else {
                self.error = error
            }
        }
        hasFinishedLoading = true
    }
    
    /// Forgets the items and selection and loads the newly active environment's, so another server's items are never shown, opened, or deleted.
    func environmentDidChange() async {
        guard activeEnvironment != loadedEnvironment else { return }
        
        items = []
        clearSelection()
        pendingDeletion = nil
        loadError = nil
        hasFinishedLoading = false
        await refresh()
    }
    
    /// Asks for confirmation before deleting `item`. The confirmation calls `delete(id:)`.
    func requestDeletion(of item: Item) {
        pendingDeletion = item
    }
    
    /// Deletes the item from the server its list was loaded from, refusing if the environment changed since.
    func delete(id: String) async {
        guard let environment = loadedEnvironment, environment == activeEnvironment else {
            error = .environmentChanged(openedFrom: loadedEnvironment ?? activeEnvironment)
            return
        }
        
        do {
            try await deleteItem(id, environment)
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
        generation += 1
        if let index = items.firstIndex(where: { $0.id == item.id }) {
            items[index] = item
        } else {
            items.insert(item, at: 0)
        }
        isLoading = false
    }
    
    func remove(id: String) {
        generation += 1
        items.removeAll { $0.id == id }
        if selectedID == id { selectedID = nil }
        isLoading = false
    }
}

// MARK: - Posts

typealias PostsViewModel = ContentListViewModel<PostPreview>

extension ContentListViewModel where Item == PostPreview {
    /// - Parameter drafts: Where editors save drafts. A deleted post's draft is deleted with it.
    convenience init(repo: any PostRepositoryProtocol = PostRepository(), drafts: DraftStore = .live, userDefaults: UserDefaults = .standard) {
        self.init(
            userDefaults: userDefaults,
            fetch: { () async throws(APIError) -> [PostPreview] in
                try await repo.fetchPosts()
            },
            delete: { (id: String, environment: FolioEnvironment) async throws(APIError) in
                try await repo.deletePost(id: id)
                // NOTE: - A draft left behind if this fails is harmless: it's only restored for a post with this ID, and then as a stale draft to keep or discard.
                try? drafts.clear(key: PostEditorViewModel.draftKey(for: .edit(id: id), environment: environment))
            }
        )
    }
}

// MARK: - Projects

typealias ProjectsViewModel = ContentListViewModel<ProjectPreview>

extension ContentListViewModel where Item == ProjectPreview {
    /// - Parameter drafts: Where editors save drafts. A deleted project's draft is deleted with it.
    convenience init(repo: any ProjectRepositoryProtocol = ProjectRepository(), drafts: DraftStore = .live, userDefaults: UserDefaults = .standard) {
        self.init(
            userDefaults: userDefaults,
            fetch: { () async throws(APIError) -> [ProjectPreview] in
                try await repo.fetchProjects()
            },
            delete: { (id: String, environment: FolioEnvironment) async throws(APIError) in
                try await repo.deleteProject(id: id)
                // NOTE: - A draft left behind if this fails is harmless: it's only restored for a project with this ID, and then as a stale draft to keep or discard.
                try? drafts.clear(key: ProjectFormViewModel.draftKey(for: .edit(id: id), environment: environment))
            }
        )
    }
}
