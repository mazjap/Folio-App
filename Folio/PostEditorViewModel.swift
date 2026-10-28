import Foundation

@Observable
class PostEditorViewModel {
    // MARK: - State
    
    enum Mode: Equatable {
        case create
        case edit(id: String)
    }
    
    var mode: Mode
    var isLoading = false
    var isSaving = false
    var error: APIError?
    var saved: PostPreview?
    var deleted = false
    
    // MARK: - Form fields
    // Each change schedules a draft save.
    
    var id = ""                 { didSet { fieldChanged() } }
    var title = ""              { didSet { fieldChanged() } }
    var excerpt = ""            { didSet { fieldChanged() } }
    var content = ""            { didSet { fieldChanged() } }
    var tags: [String] = []     { didSet { fieldChanged() } }
    var series = ""             { didSet { fieldChanged() } }
    var heroImage = ""          { didSet { fieldChanged() } }
    var pendingHeroImage: PendingImage?
    var pendingAction: EditorAction?
    var createdAt: Date? {
        didSet {
            if !isPopulating, let created = createdAt, let updated = updatedAt, created > updated {
                updatedAt = created
            }
            fieldChanged()
        }
    }
    var updatedAt: Date?
    
    /// The post's content on the server, the baseline for Show Changes.
    private(set) var serverContent = ""
    
    /// Whether a file has been uploaded under this post's ID. A new post's ID can't change after that, or the files would be left behind under the old one.
    private(set) var hasUploadedFiles = false
    
    let draftSession: DraftSession<PostDraft>
    
    @ObservationIgnored private let repo: any PostRepositoryProtocol
    @ObservationIgnored private let mediaRepo: any MediaRepositoryProtocol
    @ObservationIgnored private var isPopulating = false
    @ObservationIgnored private var serverUpdatedAt: Date?
    @ObservationIgnored private var serverHeroImage = ""
    
    // MARK: - Init
    
    init(
        mode: Mode,
        repo: any PostRepositoryProtocol = PostRepository(),
        mediaRepo: any MediaRepositoryProtocol = MediaRepository(),
        drafts: DraftStore = .live
    ) {
        self.mode = mode
        self.repo = repo
        self.mediaRepo = mediaRepo
        self.draftSession = DraftSession(key: Self.draftKey(for: mode), store: drafts)
    }
    
    // MARK: - Computed Properties
    
    /// The ID the post is saved under: the slug typed in for a new post.
    var currentID: String {
        switch mode {
        case .create: id.slugified
        case let .edit(editID): editID
        }
    }
    
    /// Whether images can be uploaded yet. A new post needs an ID first, since uploads are stored under it.
    var canUploadFiles: Bool {
        !currentID.isEmpty
    }
    
    var estimatedReadingTime: Int {
        max(1, Int(ceil(Double(content.split(whereSeparator: \.isWhitespace).count) / 200.0)))
    }
    
    var hasDraft: Bool {
        draftSession.hasDraft
    }
    
    /// Whether the restored draft was started from an older version of the post than the server's. Cleared once the user decides what to do with it.
    var isDraftStale: Bool {
        get { draftSession.isStale }
        set { draftSession.isStale = newValue }
    }
    
    static func draftKey(for mode: Mode) -> String {
        switch mode {
        case .create: "post-new"
        case let .edit(id): "post-\(id)"
        }
    }
    
    private var currentDraft: PostDraft {
        PostDraft(
            id: id,
            title: title,
            excerpt: excerpt,
            content: content,
            tags: tags,
            heroImage: heroImage,
            series: series,
            createdAt: createdAt,
            serverUpdatedAt: serverUpdatedAt,
            savedAt: .now
        )
    }
    
    // MARK: - Actions
    
    func load() async {
        guard case let .edit(id) = mode else {
            draftSession.setBaseline(currentDraft)
            if let draft = draftSession.restore() { populate(fromDraft: draft) }
            return
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let detail = try await repo.fetchPost(withId: id)
            populate(from: detail)
            draftSession.setBaseline(currentDraft)
            // Unpublished changes take priority over the server's version.
            if let draft = draftSession.restore() { populate(fromDraft: draft) }
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
    
    func save() async {
        isSaving = true
        defer { isSaving = false }
        
        do {
            if let pendingHeroImage {
                heroImage = try await upload(pendingHeroImage)
                self.pendingHeroImage = nil
            }
            
            let result: PostDetail
            switch mode {
            case .create:
                result = try await repo.createPost(buildDetail())
            case let .edit(id):
                result = try await repo.updatePost(id: id, fields: buildUpdate())
            }
            
            draftSession.discard()
            
            let previousHeroImage = serverHeroImage
            mode = .edit(id: result.id)
            draftSession.key = Self.draftKey(for: mode)
            populate(from: result)
            draftSession.setBaseline(currentDraft)
            saved = result.preview
            
            try await mediaRepo.deleteUnusedFiles(previous: [previousHeroImage], current: [heroImage], text: content, context: .posts, id: result.id)
        } catch {
            self.error = error
        }
    }
    
    func delete() async {
        guard case let .edit(id) = mode else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            try await repo.deletePost(id: id)
            draftSession.discard()
            deleted = true
        } catch {
            self.error = error
        }
    }
    
    /// Deletes the draft and goes back to the version the editor loaded.
    func discardDraft() {
        draftSession.discard()
        pendingHeroImage = nil
        if let baseline = draftSession.baseline {
            populate(fromDraft: baseline)
        }
    }
    
    /// Keeps a draft that was started from an older version of the post.
    func keepStaleDraft() {
        draftSession.isStale = false
        draftSession.save(currentDraft)
    }
    
    /// Saves the draft now, when the editor closes.
    func saveDraftNow() {
        guard !deleted else { return }
        
        draftSession.save(currentDraft)
    }
    
    func uploadInlineImage(_ image: PendingImage) async {
        guard canUploadFiles else { return }
        
        do {
            let path = try await upload(image)
            pendingAction = .insertText("![](\(path))")
        } catch {
            self.error = error
        }
    }
    
    func computeDiffRanges() -> [NSRange] {
        computeChangedLineRanges(from: serverContent, to: content)
    }
    
    // MARK: - Helpers
    
    private func fieldChanged() {
        guard !isPopulating else { return }
        
        draftSession.scheduleSave(currentDraft)
    }
    
    private func upload(_ image: PendingImage) async throws(APIError) -> String {
        let path = try await mediaRepo.upload(image, context: .posts, id: currentID)
        hasUploadedFiles = true
        return path
    }
    
    private func populate(fromDraft draft: PostDraft) {
        isPopulating = true
        defer { isPopulating = false }
        
        if case .create = mode { id = draft.id }
        title = draft.title
        excerpt = draft.excerpt
        content = draft.content
        tags = draft.tags
        heroImage = draft.heroImage
        series = draft.series
        if let draftCreatedAt = draft.createdAt { createdAt = draftCreatedAt }
    }
    
    private func populate(from detail: PostDetail) {
        isPopulating = true
        defer { isPopulating = false }
        
        serverContent = detail.content
        serverUpdatedAt = detail.updatedAt
        serverHeroImage = detail.heroImage ?? ""
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
            id: currentID,
            title: title,
            excerpt: excerpt,
            heroImage: heroImage.isEmpty ? nil : heroImage,
            tags: tags,
            createdAt: createdAt ?? .now,
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
            series: series.isEmpty ? nil : series,
            createdAt: createdAt
        )
    }
}
