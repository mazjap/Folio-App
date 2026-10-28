import Foundation

@Observable
class ProjectFormViewModel {
    // MARK: - State
    
    enum Mode: Equatable {
        case create
        case edit(id: String)
    }
    
    var mode: Mode
    var isLoading = false
    var isSaving = false
    var isUploadingMedia = false
    var error: APIError?
    var saved: ProjectPreview?
    var deleted = false
    
    // MARK: - Form fields
    // Each change schedules a draft save.
    
    var id = ""                         { didSet { fieldChanged() } }
    var title = ""                      { didSet { fieldChanged() } }
    var tagline = ""                    { didSet { fieldChanged() } }
    var category = ""                   { didSet { fieldChanged() } }
    var status = ProjectStatus.active   { didSet { fieldChanged() } }
    var featured = false                { didSet { fieldChanged() } }
    var description = ""                { didSet { fieldChanged() } }
    var techStack: [String] = []        { didSet { fieldChanged() } }
    var links: [String: String] = [:]   { didSet { fieldChanged() } }
    var media: [MediaItem] = []         { didSet { fieldChanged() } }
    var heroImage = ""                  { didSet { fieldChanged() } }
    var pendingHeroImage: PendingImage?
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
    
    /// The project's description on the server, the baseline for Show Changes.
    private(set) var serverDescription = ""
    
    /// Whether a file has been uploaded under this project's ID. A new project's ID can't change after that, or the files would be left behind under the old one.
    private(set) var hasUploadedFiles = false
    
    let draftSession: DraftSession<ProjectDraft>
    
    @ObservationIgnored private let repo: any ProjectRepositoryProtocol
    @ObservationIgnored private let mediaRepo: any MediaRepositoryProtocol
    @ObservationIgnored private var isPopulating = false
    @ObservationIgnored private var serverUpdatedAt: Date?
    @ObservationIgnored private var serverHeroImage = ""
    @ObservationIgnored private var serverMedia: [MediaItem] = []
    
    // MARK: - Init
    
    init(
        mode: Mode,
        repo: any ProjectRepositoryProtocol = ProjectRepository(),
        mediaRepo: any MediaRepositoryProtocol = MediaRepository(),
        drafts: DraftStore = .live
    ) {
        self.mode = mode
        self.repo = repo
        self.mediaRepo = mediaRepo
        self.draftSession = DraftSession(key: Self.draftKey(for: mode), store: drafts)
    }
    
    // MARK: - Computed Properties
    
    /// The ID the project is saved under: the slug typed in for a new project.
    var currentID: String {
        switch mode {
        case .create: id.slugified
        case let .edit(editID): editID
        }
    }
    
    /// Whether images can be uploaded yet. A new project needs an ID first, since uploads are stored under it.
    var canUploadFiles: Bool {
        !currentID.isEmpty
    }
    
    var hasDraft: Bool {
        draftSession.hasDraft
    }
    
    /// Whether the restored draft was started from an older version of the project than the server's. Cleared once the user decides what to do with it.
    var isDraftStale: Bool {
        get { draftSession.isStale }
        set { draftSession.isStale = newValue }
    }
    
    static func draftKey(for mode: Mode) -> String {
        switch mode {
        case .create: "project-new"
        case let .edit(id): "project-\(id)"
        }
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
            let detail = try await repo.fetchProject(withId: id)
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
            
            let result: ProjectDetail
            switch mode {
            case .create:
                result = try await repo.createProject(buildDetail())
            case let .edit(id):
                result = try await repo.updateProject(id: id, fields: buildUpdate())
            }
            
            draftSession.discard()
            
            let previousFiles = [serverHeroImage] + serverMedia.map(\.url)
            mode = .edit(id: result.id)
            draftSession.key = Self.draftKey(for: mode)
            populate(from: result)
            draftSession.setBaseline(currentDraft)
            saved = result.preview
            
            try await mediaRepo.deleteUnusedFiles(
                previous: previousFiles,
                current: [heroImage] + media.map(\.url),
                text: description,
                context: .projects,
                id: result.id
            )
        } catch {
            self.error = error
        }
    }
    
    func delete() async {
        guard case let .edit(id) = mode else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            try await repo.deleteProject(id: id)
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
    
    /// Keeps a draft that was started from an older version of the project.
    func keepStaleDraft() {
        draftSession.isStale = false
        draftSession.save(currentDraft)
    }
    
    /// Saves the draft now, when the editor closes.
    func saveDraftNow() {
        guard !deleted else { return }
        
        draftSession.save(currentDraft)
    }
    
    /// Uploads images to the gallery. They're removed from the server again if the project is saved without them.
    func addMedia(_ images: [PendingImage]) async {
        guard canUploadFiles else { return }
        
        isUploadingMedia = true
        defer { isUploadingMedia = false }
        
        for image in images {
            do {
                let path = try await upload(image)
                media.append(MediaItem(type: .image, url: path, caption: nil))
            } catch {
                self.error = error
                return
            }
        }
    }
    
    func uploadInlineImageToDescription(_ image: PendingImage) async {
        guard canUploadFiles else { return }
        
        do {
            let path = try await upload(image)
            pendingDescriptionAction = .insertText("![](\(path))")
        } catch {
            self.error = error
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
    
    private func upload(_ image: PendingImage) async throws(APIError) -> String {
        let path = try await mediaRepo.upload(image, context: .projects, id: currentID)
        hasUploadedFiles = true
        return path
    }
    
    private func populate(fromDraft draft: ProjectDraft) {
        isPopulating = true
        defer { isPopulating = false }
        
        if case .create = mode { id = draft.id }
        title = draft.title
        tagline = draft.tagline
        category = draft.category
        status = draft.status
        featured = draft.featured
        description = draft.description
        heroImage = draft.heroImage
        techStack = draft.techStack
        links = draft.links
        if let draftMedia = draft.media { media = draftMedia }
        if let draftCreatedAt = draft.createdAt { createdAt = draftCreatedAt }
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
