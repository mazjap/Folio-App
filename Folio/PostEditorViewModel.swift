import Foundation

@Observable
class PostEditorViewModel {
    // MARK: - State
    
    enum Mode: Equatable {
        case create
        case edit(id: String)
    }
    
    var mode: Mode
    private(set) var loadState = EditorLoadState.loading
    var isSaving = false
    var error: (any LocalizedError)?
    var saved: PostPreview?
    var deleted = false
    
    /// The environment the editor was opened from. Saves, uploads, and deletes go only to its server, so switching environments while editing can't change another server's post.
    let environment: FolioEnvironment
    
    // MARK: - Form fields
    // Each change schedules a draft save.
    
    var id = ""                             { didSet { fieldChanged() } }
    var title = ""                          { didSet { fieldChanged() } }
    var excerpt = ""                        { didSet { fieldChanged() } }
    var content = ""                        { didSet { fieldChanged() } }
    var tags: [String] = []                 { didSet { fieldChanged() } }
    var series = ""                         { didSet { fieldChanged() } }
    var heroImage = ""                      { didSet { fieldChanged() } }
    var pendingHeroImage: PendingImage?     { didSet { fieldChanged() } }
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
    
    /// The post's content on the server, the baseline for Highlight Changed Lines.
    private(set) var serverContent = ""
    
    /// Files uploaded while editing that the server's version doesn't use yet. A new post's ID can't change once there are any, or they'd be left behind under the old one, and any still unused when the post is saved are deleted.
    private(set) var uploadedFiles: [String] = [] { didSet { fieldChanged() } }
    
    /// How many uploads are in flight. A new item's ID locks as soon as one starts, so it can't change while files are being stored under it.
    private(set) var activeUploads = 0
    
    let draftSession: DraftSession<PostDraft>
    
    @ObservationIgnored private let repo: any PostRepositoryProtocol
    @ObservationIgnored private let mediaRepo: any MediaRepositoryProtocol
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var isPopulating = false
    @ObservationIgnored private var serverUpdatedAt: Date?
    @ObservationIgnored private var serverHeroImage = ""
    
    // MARK: - Init
    
    init(
        mode: Mode,
        repo: any PostRepositoryProtocol = PostRepository(),
        mediaRepo: any MediaRepositoryProtocol = MediaRepository(),
        drafts: DraftStore = .live,
        userDefaults: UserDefaults = .standard
    ) {
        let environment = ServerSettings(userDefaults: userDefaults).activeEnvironment
        self.mode = mode
        self.repo = repo
        self.mediaRepo = mediaRepo
        self.userDefaults = userDefaults
        self.environment = environment
        self.draftSession = DraftSession(key: Self.draftKey(for: mode, environment: environment), legacyKey: Self.legacyDraftKey(for: mode), store: drafts)
        draftSession.onError = { [weak self] error in self?.error = error }
    }
    
    // MARK: - Computed Properties
    
    /// The ID the post is saved under: the slug typed in for a new post.
    var currentID: String {
        switch mode {
        case .create: id.slugified
        case let .edit(editID): editID
        }
    }
    
    /// Whether images can be uploaded yet. A new post needs a valid ID first, since uploads are stored under it.
    var canUploadFiles: Bool {
        switch mode {
        case .create: ContentRules.slugIssue(for: id) == nil
        case .edit: loadState == .loaded
        }
    }
    
    var hasUploadedFiles: Bool {
        !uploadedFiles.isEmpty || activeUploads > 0
    }
    
    /// What's stopping the post from being saved, as the server would reject it.
    var validationIssues: [String] {
        var issues: [String] = []
        if case .create = mode, let issue = ContentRules.slugIssue(for: id) { issues.append(issue) }
        let checks = [
            ContentRules.requiredTextIssue("Title", title, max: 200),
            ContentRules.lengthIssue("The excerpt", excerpt, max: 1000),
            ContentRules.lengthIssue("The series", series, max: 100),
            ContentRules.lengthIssue("The post", content, max: ContentRules.maxMarkdownLength),
            ContentRules.listIssue("Tags", tags, maxItems: 30, maxLength: 40)
        ]
        issues += checks.compactMap(\.self)
        return issues
    }
    
    /// Whether Publish can run: the post loaded (so the server's version is known), nothing is being saved, and the fields are valid.
    var canSave: Bool {
        loadState == .loaded && !isSaving && validationIssues.isEmpty
    }
    
    var estimatedReadingTime: Int {
        max(1, Int(ceil(Double(content.split(whereSeparator: \.isWhitespace).count) / 200.0)))
    }
    
    var hasDraft: Bool {
        draftSession.hasDraft
    }
    
    /// Whether the restored draft was started from an older version of the post than the server's, or before drafts were kept apart by environment. Cleared once the user decides what to do with it.
    var isDraftStale: Bool {
        get { draftSession.isStale }
        set { draftSession.isStale = newValue }
    }
    
    var isDraftLegacy: Bool {
        draftSession.isLegacy
    }
    
    /// The draft key, namespaced by environment so Development and Production drafts of the same post stay apart. New posts use `new-post`, which no post ID can collide with.
    static func draftKey(for mode: Mode, environment: FolioEnvironment) -> String {
        switch mode {
        case .create: "\(environment.rawValue).new-post"
        case let .edit(id): "\(environment.rawValue).post-\(id)"
        }
    }
    
    /// Where drafts were saved before they were kept apart by environment.
    static func legacyDraftKey(for mode: Mode) -> String {
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
            pendingHeroImage: pendingHeroImage,
            // NOTE: - `nil` when empty, matching drafts saved before this field existed.
            uploadedFiles: uploadedFiles.isEmpty ? nil : uploadedFiles,
            serverUpdatedAt: serverUpdatedAt,
            savedAt: .now
        )
    }
    
    /// A draft with every field empty, the baseline while the post couldn't be loaded.
    private var emptyDraft: PostDraft {
        PostDraft(id: "", title: "", excerpt: "", content: "", tags: [], heroImage: "", series: "", createdAt: nil, pendingHeroImage: nil, uploadedFiles: nil, serverUpdatedAt: nil, savedAt: .now)
    }
    
    // MARK: - Actions
    
    func load() async {
        guard case let .edit(id) = mode else {
            draftSession.setBaseline(currentDraft)
            if let draft = draftSession.restore() { populate(fromDraft: draft) }
            loadState = .loaded
            return
        }
        
        if case .failed(_, showsDraft: true) = loadState {
            // Keep what was edited offline: it's restored over the server's version once that loads.
            draftSession.save(currentDraft)
        }
        loadState = .loading
        
        do {
            let detail = try await repo.fetchPost(withId: id)
            populate(from: detail)
            draftSession.setBaseline(currentDraft)
            // Unpublished changes take priority over the server's version.
            if let draft = draftSession.restore() { populate(fromDraft: draft) }
            loadState = .loaded
        } catch {
            guard !error.isCancellation else { return }
            
            // NOTE: - A saved draft is still shown offline, but it can't be published until the server's version loads, so publishing never replaces a version Folio hasn't seen.
            if let draft = draftSession.restoreOffline(empty: emptyDraft) {
                populate(fromDraft: draft)
                serverUpdatedAt = draft.serverUpdatedAt
                loadState = .failed(message: error.localizedDescription, showsDraft: true)
            } else {
                loadState = .failed(message: error.localizedDescription, showsDraft: false)
            }
        }
    }
    
    func save() async {
        guard canSave else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            if let pendingHeroImage {
                heroImage = try await upload(pendingHeroImage)
                self.pendingHeroImage = nil
            }
            
            let submitted = currentDraft
            try checkEnvironment()
            let result: PostDetail
            switch mode {
            case .create:
                result = try await repo.createPost(buildDetail())
            case let .edit(id):
                result = try await repo.updatePost(id: id, fields: buildUpdate())
            }
            
            // Anything typed while the post was saving is kept as a draft over what was saved.
            let edited = currentDraft
            let candidates = [serverHeroImage] + uploadedFiles
            draftSession.discard()
            
            mode = .edit(id: result.id)
            draftSession.key = Self.draftKey(for: mode, environment: environment)
            populate(from: result)
            draftSession.setBaseline(currentDraft)
            if !edited.hasSameContent(as: submitted) { populate(fromDraft: edited) }
            
            // Files the saved post or the newer edits use are kept.
            let cleanup = await mediaRepo.deleteUnusedFiles(
                previous: candidates,
                current: [result.heroImage ?? "", edited.heroImage],
                text: result.content + "\n" + edited.content,
                context: .posts,
                id: result.id,
                check: checkEnvironment
            )
            // Uploads only the newer edits use stay tracked, as do files that couldn't be deleted, so the next save tries again.
            let usedOnlyByEdits = (edited.uploadedFiles ?? []).filter { path in
                path != result.heroImage && !result.content.contains(path) && (path == edited.heroImage || edited.content.contains(path))
            }
            uploadedFiles = Array(Set(cleanup.failed + usedOnlyByEdits)).sorted()
            draftSession.save(currentDraft)
            
            saved = result.preview
            if let cleanupError = cleanup.error, !cleanupError.isCancellation {
                error = APIError.cleanupFailed(count: cleanup.failed.count, underlying: cleanupError.localizedDescription)
            }
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
    
    func delete() async {
        guard case let .edit(id) = mode, !isSaving else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            try checkEnvironment()
            try await repo.deletePost(id: id)
            draftSession.discard()
            deleted = true
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
    
    /// Deletes the draft and goes back to the version the editor loaded. Images uploaded for the draft that the loaded version doesn't use are deleted.
    func discardDraft() {
        let uploads = uploadedFiles
        let owner = currentID
        draftSession.discard()
        if let baseline = draftSession.baseline {
            populate(fromDraft: baseline)
        }
        
        guard !uploads.isEmpty, !owner.isEmpty else { return }
        
        Task { [weak self, heroImage, content] in
            guard let self else { return }
            
            let cleanup = await mediaRepo.deleteUnusedFiles(previous: uploads, current: [heroImage], text: content, context: .posts, id: owner, check: checkEnvironment)
            if let cleanupError = cleanup.error, !cleanupError.isCancellation {
                error = cleanupError
            }
        }
    }
    
    /// Keeps a draft that was started from an older version of the post, or before drafts were kept apart by environment.
    func keepStaleDraft() {
        draftSession.isStale = false
        draftSession.save(currentDraft)
    }
    
    /// Saves the draft now, when the editor closes or the app goes to the background.
    func saveDraftNow() {
        guard !deleted else { return }
        
        draftSession.save(currentDraft)
    }
    
    /// Uploads an image and inserts it with its alt text selected, ready to describe it.
    func uploadInlineImage(_ image: PendingImage) async {
        guard canUploadFiles else { return }
        
        do {
            let path = try await upload(image)
            pendingAction = .wrap(prefix: "![", suffix: "](\(path))", placeholder: "Describe the image")
        } catch {
            if !error.isCancellation { self.error = error }
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
    
    /// Throws if the environment changed since the editor opened, before anything is sent to the server.
    private func checkEnvironment() throws(APIError) {
        guard ServerSettings(userDefaults: userDefaults).activeEnvironment == environment else {
            throw .environmentChanged(openedFrom: environment)
        }
    }
    
    private func upload(_ image: PendingImage) async throws(APIError) -> String {
        try checkEnvironment()
        // NOTE: - The ID is captured, and the ID field locked, before uploading.
        let owner = currentID
        activeUploads += 1
        defer { activeUploads -= 1 }
        
        let path = try await mediaRepo.upload(image, context: .posts, id: owner)
        uploadedFiles.append(path)
        return path
    }
    
    private func populate(fromDraft draft: PostDraft) {
        isPopulating = true
        defer { isPopulating = false }
        
        if case .create = mode {
            id = draft.id
            createdAt = draft.createdAt
        } else if let draftCreatedAt = draft.createdAt {
            createdAt = draftCreatedAt
        }
        title = draft.title
        excerpt = draft.excerpt
        content = draft.content
        tags = draft.tags
        heroImage = draft.heroImage
        pendingHeroImage = draft.pendingHeroImage
        uploadedFiles = draft.uploadedFiles ?? []
        series = draft.series
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
        uploadedFiles = []
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
