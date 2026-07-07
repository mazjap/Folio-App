import Foundation

@Observable
class ProjectFormViewModel {
    // MARK: - State

    enum Mode { case create, edit(id: String) }

    var mode: Mode
    var isLoading = false
    var isSaving = false
    var error: APIError?
    var saved: ProjectPreview?
    var deleted = false
    var hasDraft = false

    // MARK: - Form fields
    // didSet schedules a debounced draft save on every field change.

    var id = ""                     { didSet { scheduleAutosave() } }
    var title = ""                  { didSet { scheduleAutosave() } }
    var tagline = ""                { didSet { scheduleAutosave() } }
    var category = ""               { didSet { scheduleAutosave() } }
    var status = ProjectStatus.active { didSet { scheduleAutosave() } }
    var featured = false            { didSet { scheduleAutosave() } }
    var description = ""            { didSet { scheduleAutosave() } }
    var techStack: [String] = []    { didSet { scheduleAutosave() } }
    var links: [String: String] = [:] { didSet { scheduleAutosave() } }
    var heroImage = ""
    var pendingHeroImage: PendingImage?
    var pendingDescriptionAction: EditorAction?
    var media: [MediaItem] = []
    var createdAt: Date?
    var updatedAt: Date?
    private(set) var serverDescription = ""

    // MARK: - Init

    init(mode: Mode) {
        self.mode = mode
    }

    deinit { autosaveTask?.cancel() }

    private let repo = ProjectRepository()
    private let mediaRepo = MediaRepository()
    private var autosaveTask: Task<Void, Never>?
    private var isPopulating = false

    // MARK: - Actions

    func load() async {
        guard case .edit(let id) = mode else {
            if let draft = DraftStore.load(ProjectDraft.self, key: draftKey) {
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
            let detail = try await repo.fetchProject(withId: id)
            isPopulating = true
            populate(from: detail)
            if let draft = DraftStore.load(ProjectDraft.self, key: draftKey) {
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
        let keyBeforeSave = draftKey
        do {
            if let pending = pendingHeroImage {
                let url = try await mediaRepo.upload(
                    fileData: pending.data,
                    fileName: "\(UUID().uuidString).\(pending.ext)",
                    mimeType: pending.mimeType,
                    context: .projects,
                    id: currentID
                )
                heroImage = url
                pendingHeroImage = nil
            }
            switch mode {
            case .create:
                let detail = buildDetail()
                let created = try await repo.createProject(detail)
                mode = .edit(id: created.id)
                saved = created.preview
            case .edit(let id):
                let fields = buildUpdate()
                let updated = try await repo.updateProject(id: id, fields: fields)
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
            try await repo.deleteProject(id: id)
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
            id = ""; title = ""; tagline = ""; category = ""
            status = .active; featured = false; description = ""
            heroImage = ""; techStack = []; links = [:]
            pendingHeroImage = nil
            isPopulating = false
        case .edit:
            Task { await load() }
        }
    }

    func saveDraft() {
        guard !isPopulating else { return }
        let draft = ProjectDraft(
            id: currentID,
            title: title,
            tagline: tagline,
            category: category,
            status: status,
            featured: featured,
            description: description,
            heroImage: heroImage,
            techStack: techStack,
            links: links,
            savedAt: Date()
        )
        DraftStore.save(draft, key: draftKey)
    }

    // MARK: - Helpers

    func uploadInlineImageToDescription(data: Data, mimeType: String, ext: String) async {
        let projectID = currentID
        guard !projectID.isEmpty else { return }
        do {
            let path = try await mediaRepo.upload(
                fileData: data,
                fileName: "\(UUID().uuidString).\(ext)",
                mimeType: mimeType,
                context: .projects,
                id: projectID
            )
            pendingDescriptionAction = .insertText("![](\(path))")
        } catch {
            self.error = error
        }
    }

    func computeDiffDescriptionRanges() -> [NSRange] {
        computeChangedLineRanges(from: serverDescription, to: description)
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
        case .create: return "project-new"
        case .edit(let id): return "project-\(id)"
        }
    }

    private func populateFromDraft(_ draft: ProjectDraft) {
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
    }

    private func populate(from detail: ProjectDetail) {
        serverDescription = detail.description
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
            id: id.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: " ", with: "-"),
            title: title,
            tagline: tagline,
            heroImage: heroImage,
            category: category.isEmpty ? nil : category,
            status: status,
            featured: featured,
            createdAt: Date(),
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
            heroImage: heroImage.isEmpty ? nil : heroImage,
            category: category.isEmpty ? nil : category,
            status: status,
            featured: featured,
            techStack: techStack,
            links: links,
            media: media
        )
    }
}
