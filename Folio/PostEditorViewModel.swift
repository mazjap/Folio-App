import Foundation

@Observable
class PostEditorViewModel {
    // MARK: - State

    enum Mode { case create, edit(id: String) }

    var mode: Mode
    var isLoading = false
    var isSaving = false
    var error: APIError?
    var saved: PostPreview?
    var deleted = false
    var hasDraft = false

    // MARK: - Form fields
    // didSet schedules a debounced draft save on every field change.

    var id = ""         { didSet { scheduleAutosave() } }
    var title = ""      { didSet { scheduleAutosave() } }
    var excerpt = ""    { didSet { scheduleAutosave() } }
    var content = ""    { didSet { scheduleAutosave() } }
    var tags: [String] = [] { didSet { scheduleAutosave() } }
    var series = ""     { didSet { scheduleAutosave() } }
    var heroImage = ""
    var pendingHeroImage: PendingImage?
    var pendingAction: EditorAction?
    var createdAt: Date?
    var updatedAt: Date?
    private(set) var serverContent = ""

    var estimatedReadingTime: Int {
        max(1, Int(ceil(Double(content.split(separator: " ").count) / 200.0)))
    }

    // MARK: - Init

    init(mode: Mode) {
        self.mode = mode
    }

    deinit { autosaveTask?.cancel() }

    private let repo = PostRepository()
    private let mediaRepo = MediaRepository()
    private var autosaveTask: Task<Void, Never>?
    private var isPopulating = false

    // MARK: - Actions

    func load() async {
        guard case .edit(let id) = mode else {
            // Create mode: restore any in-progress draft.
            if let draft = DraftStore.load(PostDraft.self, key: draftKey) {
                isPopulating = true
                populateFromDraft(draft)
                isPopulating = false
                hasDraft = true
            }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await repo.fetchPost(withId: id)
            isPopulating = true
            populate(from: detail)
            // Restore draft on top of server data — user's unsynced work takes priority.
            if let draft = DraftStore.load(PostDraft.self, key: draftKey) {
                populateFromDraft(draft)
                hasDraft = true
            }
            isPopulating = false
        } catch {
            isPopulating = false
            if !error.isCancellation { self.error = error }
        }
    }

    func save() async {
        isSaving = true
        defer { isSaving = false }
        let keyBeforeSave = draftKey  // Capture before mode may change (create → edit)
        do {
            if let pending = pendingHeroImage {
                let url = try await mediaRepo.upload(
                    fileData: pending.data,
                    fileName: "\(UUID().uuidString).\(pending.ext)",
                    mimeType: pending.mimeType,
                    context: .posts,
                    id: currentID
                )
                heroImage = url
                pendingHeroImage = nil
            }
            switch mode {
            case .create:
                let detail = buildDetail()
                let created = try await repo.createPost(detail)
                mode = .edit(id: created.id)
                isPopulating = true
                populate(from: created)
                isPopulating = false
                saved = created.preview
            case .edit(let id):
                let fields = buildUpdate()
                let updated = try await repo.updatePost(id: id, fields: fields)
                isPopulating = true
                populate(from: updated)
                isPopulating = false
                saved = updated.preview
            }
            DraftStore.clear(key: keyBeforeSave)
            hasDraft = false
        } catch {
            self.error = error
        }
    }

    func delete() async {
        guard case .edit(let id) = mode else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await repo.deletePost(id: id)
            DraftStore.clear(key: draftKey)
            deleted = true
        } catch {
            self.error = error
        }
    }

    func discardDraft() {
        DraftStore.clear(key: draftKey)
        hasDraft = false
        switch mode {
        case .create:
            isPopulating = true
            id = ""; title = ""; excerpt = ""; content = ""
            tags = []; heroImage = ""; series = ""
            pendingHeroImage = nil
            isPopulating = false
        case .edit:
            Task { await load() }
        }
    }

    func saveDraft() {
        guard !isPopulating else { return }
        let draft = PostDraft(
            id: currentID,
            title: title,
            excerpt: excerpt,
            content: content,
            tags: tags,
            heroImage: heroImage,
            series: series,
            savedAt: Date()
        )
        DraftStore.save(draft, key: draftKey)
    }

    // MARK: - Helpers

    func uploadInlineImage(data: Data, mimeType: String, ext: String) async {
        let postID = currentID
        guard !postID.isEmpty else { return }
        do {
            let path = try await mediaRepo.upload(
                fileData: data,
                fileName: "\(UUID().uuidString).\(ext)",
                mimeType: mimeType,
                context: .posts,
                id: postID
            )
            pendingAction = .insertText("![](\(path))")
        } catch {
            self.error = error
        }
    }

    func computeDiffRanges() -> [NSRange] {
        computeChangedLineRanges(from: serverContent, to: content)
    }

    func scheduleAutosave() {
        guard !isPopulating else { return }
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.saveDraft()
        }
    }

    var currentID: String {
        switch mode {
        case .create:
            return id.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-")
        case .edit(let editID):
            return editID
        }
    }

    private var draftKey: String {
        switch mode {
        case .create: return "post-new"
        case .edit(let id): return "post-\(id)"
        }
    }

    private func populateFromDraft(_ draft: PostDraft) {
        if case .create = mode { id = draft.id }
        title = draft.title
        excerpt = draft.excerpt
        content = draft.content
        tags = draft.tags
        heroImage = draft.heroImage
        series = draft.series
    }

    private func populate(from detail: PostDetail) {
        serverContent = detail.content
        id = detail.id
        title = detail.title
        excerpt = detail.excerpt
        content = detail.content
        tags = detail.tags
        heroImage = detail.heroImage ?? ""
        pendingHeroImage = nil
        series = detail.series ?? ""
        createdAt = detail.createdAt
        updatedAt = detail.updatedAt
    }

    private func buildDetail() -> PostDetail {
        PostDetail(
            content: content,
            id: id.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-"),
            title: title,
            excerpt: excerpt,
            heroImage: heroImage.isEmpty ? nil : heroImage,
            tags: tags,
            createdAt: Date(),
            updatedAt: nil,
            readingTime: estimatedReadingTime,
            series: series.isEmpty ? nil : series
        )
    }

    private func buildUpdate() -> PostUpdate {
        PostUpdate(
            title: title,
            excerpt: excerpt,
            content: content,
            tags: tags,
            heroImage: heroImage.isEmpty ? nil : heroImage,
            series: series.isEmpty ? nil : series
        )
    }
}
