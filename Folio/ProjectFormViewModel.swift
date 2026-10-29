import Foundation

@Observable
class ProjectFormViewModel {
    // MARK: - State
    
    enum Mode: Equatable {
        case create
        case edit(id: String)
    }
    
    var mode: Mode
    private(set) var loadState = EditorLoadState.loading
    var isSaving = false
    var isUploadingMedia = false
    var error: (any LocalizedError)?
    var saved: ProjectPreview?
    var deleted = false
    
    /// The environment the editor was opened from. Saves, uploads, and deletes go only to its server, so switching environments while editing can't change another server's project.
    let environment: FolioEnvironment
    
    // MARK: - Form fields
    // Each change schedules a draft save.
    
    var id = ""                             { didSet { fieldChanged() } }
    var title = ""                          { didSet { fieldChanged() } }
    var tagline = ""                        { didSet { fieldChanged() } }
    var category = ""                       { didSet { fieldChanged() } }
    var status = ProjectStatus.active       { didSet { fieldChanged() } }
    var featured = false                    { didSet { fieldChanged() } }
    var description = ""                    { didSet { fieldChanged() } }
    var techStack: [String] = []            { didSet { fieldChanged() } }
    var links: [String: String] = [:]       { didSet { fieldChanged() } }
    var media: [MediaItem] = []             { didSet { fieldChanged() } }
    var heroImage = ""                      { didSet { fieldChanged() } }
    var pendingHeroImage: PendingImage?     { didSet { fieldChanged() } }
    var pendingDescriptionAction: EditorAction?
    var createdAt: Date? {
        didSet {
            if !isPopulating, let created = createdAt, let updated = updatedAt, created > updated {
                updatedAt = created
            }
            fieldChanged()
        }
    }
    var updatedAt: Date?
    
    /// The project's description on the server, the baseline for Highlight Changed Lines.
    private(set) var serverDescription = ""
    
    /// Files uploaded while editing that the server's version doesn't use yet. A new project's ID can't change once there are any, or they'd be left behind under the old one, and any still unused when the project is saved are deleted.
    private(set) var uploadedFiles: [String] = [] { didSet { fieldChanged() } }
    
    /// How many uploads are in flight. A new item's ID locks as soon as one starts, so it can't change while files are being stored under it.
    private(set) var activeUploads = 0
    
    let draftSession: DraftSession<ProjectDraft>
    
    @ObservationIgnored private let repo: any ProjectRepositoryProtocol
    @ObservationIgnored private let mediaRepo: any MediaRepositoryProtocol
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var isPopulating = false
    @ObservationIgnored private var serverUpdatedAt: Date?
    @ObservationIgnored private var serverHeroImage = ""
    @ObservationIgnored private var serverMedia: [MediaItem] = []
    
    // MARK: - Init
    
    init(
        mode: Mode,
        repo: any ProjectRepositoryProtocol = ProjectRepository(),
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
    
    /// The ID the project is saved under: the slug typed in for a new project.
    var currentID: String {
        switch mode {
        case .create: id.slugified
        case let .edit(editID): editID
        }
    }
    
    /// Whether images can be uploaded yet. A new project needs a valid ID first, since uploads are stored under it.
    var canUploadFiles: Bool {
        switch mode {
        case .create: ContentRules.slugIssue(for: id) == nil
        case .edit: loadState == .loaded
        }
    }
    
    var hasUploadedFiles: Bool {
        !uploadedFiles.isEmpty || activeUploads > 0
    }
    
    /// What's stopping the project from being saved, as the server would reject it.
    var validationIssues: [String] {
        var issues: [String] = []
        if case .create = mode, let issue = ContentRules.slugIssue(for: id) { issues.append(issue) }
        let checks = [
            ContentRules.requiredTextIssue("Title", title, max: 200),
            ContentRules.requiredTextIssue("Tagline", tagline, max: 300),
            ContentRules.lengthIssue("The category", category, max: 50),
            ContentRules.lengthIssue("The description", description, max: ContentRules.maxMarkdownLength),
            ContentRules.listIssue("Tech stack", techStack, maxItems: 50, maxLength: 60),
            Self.linksIssue(links),
            media.count > 100 ? "The gallery can have at most 100 items." : nil,
            media.contains { ($0.caption ?? "").count > 300 } ? "Captions can be at most 300 characters." : nil
        ]
        issues += checks.compactMap(\.self)
        return issues
    }
    
    /// Whether Save can run: the project loaded (so the server's version is known), nothing is being saved, and the fields are valid.
    var canSave: Bool {
        loadState == .loaded && !isSaving && validationIssues.isEmpty
    }
    
    var hasDraft: Bool {
        draftSession.hasDraft
    }
    
    /// Whether the restored draft was started from an older version of the project than the server's, or before drafts were kept apart by environment. Cleared once the user decides what to do with it.
    var isDraftStale: Bool {
        get { draftSession.isStale }
        set { draftSession.isStale = newValue }
    }
    
    var isDraftLegacy: Bool {
        draftSession.isLegacy
    }
    
    /// The draft key, namespaced by environment so Development and Production drafts of the same project stay apart. New projects use `new-project`, which no project ID can collide with.
    static func draftKey(for mode: Mode, environment: FolioEnvironment) -> String {
        switch mode {
        case .create: "\(environment.rawValue).new-project"
        case let .edit(id): "\(environment.rawValue).project-\(id)"
        }
    }
    
    /// Where drafts were saved before they were kept apart by environment.
    static func legacyDraftKey(for mode: Mode) -> String {
        switch mode {
        case .create: "project-new"
        case let .edit(id): "project-\(id)"
        }
    }
    
    /// Why a link can't be saved, or `nil` if it can.
    static func linkIssue(name: String, url: String) -> String? {
        if name.trimmingCharacters(in: .whitespaces).isEmpty || name.count > 50 { return "Link names must be 1–50 characters." }
        if !ContentRules.isAllowedURL(url, schemes: .webOrMail) { return "Links must be full URLs starting with https:// or mailto:." }
        return nil
    }
    
    private static func linksIssue(_ links: [String: String]) -> String? {
        if links.count > 20 { return "A project can have at most 20 links." }
        return links.sorted { $0.key < $1.key }.lazy.compactMap { linkIssue(name: $0.key, url: $0.value) }.first
    }
    
    private var currentDraft: ProjectDraft {
        ProjectDraft(
            id: id,
            title: title,
            tagline: tagline,
            category: category,
            status: status,
            featured: featured,
            description: description,
            heroImage: heroImage,
            techStack: techStack,
            links: links,
            media: media,
            createdAt: createdAt,
            pendingHeroImage: pendingHeroImage,
            // NOTE: - `nil` when empty, matching drafts saved before this field existed.
            uploadedFiles: uploadedFiles.isEmpty ? nil : uploadedFiles,
            serverUpdatedAt: serverUpdatedAt,
            savedAt: .now
        )
    }
    
    /// A draft with every field empty, the baseline while the project couldn't be loaded.
    private var emptyDraft: ProjectDraft {
        ProjectDraft(id: "", title: "", tagline: "", category: "", status: .active, featured: false, description: "", heroImage: "", techStack: [], links: [:], media: [], createdAt: nil, pendingHeroImage: nil, uploadedFiles: nil, serverUpdatedAt: nil, savedAt: .now)
    }
    
    /// Every file the project shows: its hero image and gallery.
    private static func files(heroImage: String, media: [MediaItem]) -> [String] {
        [heroImage] + media.map(\.url)
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
            let detail = try await repo.fetchProject(withId: id)
            populate(from: detail)
            draftSession.setBaseline(currentDraft)
            // Unpublished changes take priority over the server's version.
            if let draft = draftSession.restore() { populate(fromDraft: draft) }
            loadState = .loaded
        } catch {
            guard !error.isCancellation else { return }
            
            // NOTE: - A saved draft is still shown offline, but it can't be saved until the server's version loads, so saving never replaces a version Folio hasn't seen.
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
            let result: ProjectDetail
            switch mode {
            case .create:
                result = try await repo.createProject(buildDetail())
            case let .edit(id):
                result = try await repo.updateProject(id: id, fields: buildUpdate())
            }
            
            // Anything changed while the project was saving is kept as a draft over what was saved.
            let edited = currentDraft
            let candidates = Self.files(heroImage: serverHeroImage, media: serverMedia) + uploadedFiles
            draftSession.discard()
            
            mode = .edit(id: result.id)
            draftSession.key = Self.draftKey(for: mode, environment: environment)
            populate(from: result)
            draftSession.setBaseline(currentDraft)
            if !edited.hasSameContent(as: submitted) { populate(fromDraft: edited) }
            
            // Files the saved project or the newer edits use are kept.
            let savedFiles = Self.files(heroImage: result.heroImage, media: result.media)
            let editedFiles = Self.files(heroImage: edited.heroImage, media: edited.media ?? [])
            let cleanup = await mediaRepo.deleteUnusedFiles(
                previous: candidates,
                current: savedFiles + editedFiles,
                text: result.description + "\n" + edited.description,
                context: .projects,
                id: result.id,
                check: checkEnvironment
            )
            // Uploads only the newer edits use stay tracked, as do files that couldn't be deleted, so the next save tries again.
            let usedOnlyByEdits = (edited.uploadedFiles ?? []).filter { path in
                !savedFiles.contains(path) && !result.description.contains(path) && (editedFiles.contains(path) || edited.description.contains(path))
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
            try await repo.deleteProject(id: id)
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
        
        Task { [weak self, heroImage, media, description] in
            guard let self else { return }
            
            let cleanup = await mediaRepo.deleteUnusedFiles(previous: uploads, current: Self.files(heroImage: heroImage, media: media), text: description, context: .projects, id: owner, check: checkEnvironment)
            if let cleanupError = cleanup.error, !cleanupError.isCancellation {
                error = cleanupError
            }
        }
    }
    
    /// Keeps a draft that was started from an older version of the project, or before drafts were kept apart by environment.
    func keepStaleDraft() {
        draftSession.isStale = false
        draftSession.save(currentDraft)
    }
    
    /// Saves the draft now, when the editor closes or the app goes to the background.
    func saveDraftNow() {
        guard !deleted else { return }
        
        draftSession.save(currentDraft)
    }
    
    /// Uploads images to the gallery. They're deleted from the server again if the project is saved without them.
    func addMedia(_ images: [PendingImage]) async {
        guard canUploadFiles, !isUploadingMedia else { return }
        
        isUploadingMedia = true
        defer { isUploadingMedia = false }
        
        for image in images {
            do {
                let path = try await upload(image)
                media.append(MediaItem(type: .image, url: path, caption: nil))
            } catch {
                if !error.isCancellation { self.error = error }
                return
            }
        }
    }
    
    /// Uploads an image and inserts it with its alt text selected, ready to describe it.
    func uploadInlineImageToDescription(_ image: PendingImage) async {
        guard canUploadFiles else { return }
        
        do {
            let path = try await upload(image)
            pendingDescriptionAction = .wrap(prefix: "![", suffix: "](\(path))", placeholder: "Describe the image")
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
    
    func computeDiffDescriptionRanges() -> [NSRange] {
        computeChangedLineRanges(from: serverDescription, to: description)
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
        
        let path = try await mediaRepo.upload(image, context: .projects, id: owner)
        uploadedFiles.append(path)
        return path
    }
    
    private func populate(fromDraft draft: ProjectDraft) {
        isPopulating = true
        defer { isPopulating = false }
        
        if case .create = mode {
            id = draft.id
            createdAt = draft.createdAt
        } else if let draftCreatedAt = draft.createdAt {
            createdAt = draftCreatedAt
        }
        title = draft.title
        tagline = draft.tagline
        category = draft.category
        status = draft.status
        featured = draft.featured
        description = draft.description
        heroImage = draft.heroImage
        pendingHeroImage = draft.pendingHeroImage
        uploadedFiles = draft.uploadedFiles ?? []
        techStack = draft.techStack
        links = draft.links
        if let draftMedia = draft.media { media = draftMedia }
    }
    
    private func populate(from detail: ProjectDetail) {
        isPopulating = true
        defer { isPopulating = false }
        
        serverDescription = detail.description
        serverUpdatedAt = detail.updatedAt
        serverHeroImage = detail.heroImage
        serverMedia = detail.media
        id = detail.id
        title = detail.title
        tagline = detail.tagline
        category = detail.category ?? ""
        status = detail.status
        featured = detail.featured
        description = detail.description
        heroImage = detail.heroImage
        pendingHeroImage = nil
        uploadedFiles = []
        techStack = detail.techStack
        links = detail.links
        media = detail.media
        createdAt = detail.createdAt
        updatedAt = detail.updatedAt
    }
    
    private func buildDetail() -> ProjectDetail {
        ProjectDetail(
            id: currentID,
            title: title,
            tagline: tagline,
            heroImage: heroImage,
            category: category.isEmpty ? nil : category,
            status: status,
            featured: featured,
            createdAt: createdAt ?? .now,
            updatedAt: nil,
            description: description,
            media: media,
            techStack: techStack,
            links: links
        )
    }
    
    private func buildUpdate() -> ProjectUpdate {
        ProjectUpdate(
            title: title,
            tagline: tagline,
            description: description,
            heroImage: heroImage,
            category: category.isEmpty ? nil : category,
            status: status,
            featured: featured,
            techStack: techStack,
            links: links,
            media: media,
            createdAt: createdAt
        )
    }
}
