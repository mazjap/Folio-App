import Foundation

@Observable
class AppSupportEditorViewModel {
    let appId: String
    /// Whether the page exists on the server, so saving updates it rather than creating it.
    private(set) var isEditing: Bool
    
    /// The environment the editor was opened from. Saves and deletes go only to its server.
    let environment: FolioEnvironment
    
    // MARK: - Form fields
    // Each change schedules a draft save.
    
    var appName = ""        { didSet { fieldChanged() } }
    var version = ""        { didSet { fieldChanged() } }
    var subtitle = ""       { didSet { fieldChanged() } }
    var content = ""        { didSet { fieldChanged() } }
    var contactUrl = ""     { didSet { fieldChanged() } }
    var contactText = ""    { didSet { fieldChanged() } }
    var pendingAction: EditorAction?
    
    var isSaving = false
    var error: (any LocalizedError)?
    var saved: AppSupport?
    var deleted = false
    
    let draftSession: DraftSession<AppSupportDraft>
    
    @ObservationIgnored private let repo: any AppsRepositoryProtocol
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var isPopulating = false
    
    // MARK: - Init
    
    init(appId: String, existing: AppSupport?, repo: any AppsRepositoryProtocol = AppsRepository(), drafts: DraftStore = .live, userDefaults: UserDefaults = .standard) {
        let environment = ServerSettings(userDefaults: userDefaults).activeEnvironment
        self.appId = appId
        self.repo = repo
        self.userDefaults = userDefaults
        self.environment = environment
        self.isEditing = existing != nil
        self.draftSession = DraftSession(key: Self.draftKey(appId: appId, environment: environment), store: drafts)
        draftSession.onError = { [weak self] error in self?.error = error }
        if let existing { populate(from: existing) }
    }
    
    // MARK: - Computed Properties
    
    var validationIssues: [String] {
        [
            ContentRules.requiredTextIssue("App name", appName, max: 100),
            ContentRules.requiredTextIssue("Version", version, max: 30),
            ContentRules.lengthIssue("The subtitle", subtitle, max: 300),
            ContentRules.lengthIssue("The page", content, max: ContentRules.maxMarkdownLength),
            ContentRules.optionalURLIssue("The contact URL", contactUrl, schemes: .webOrMail),
            ContentRules.lengthIssue("The contact button title", contactText, max: 100)
        ].compactMap(\.self)
    }
    
    var canSave: Bool {
        !isSaving && validationIssues.isEmpty
    }
    
    var hasDraft: Bool {
        draftSession.hasDraft
    }
    
    static func draftKey(appId: String, environment: FolioEnvironment) -> String {
        "\(environment.rawValue).app-\(appId)-support"
    }
    
    private var currentDraft: AppSupportDraft {
        AppSupportDraft(appName: appName, version: version, subtitle: subtitle, content: content, contactUrl: contactUrl, contactText: contactText, serverUpdatedAt: nil, savedAt: .now)
    }
    
    // MARK: - Actions
    
    /// Starts saving drafts, and restores one with unpublished changes.
    func load() {
        guard draftSession.baseline == nil else { return }
        
        draftSession.setBaseline(currentDraft)
        if let draft = draftSession.restore() { populate(fromDraft: draft) }
    }
    
    func save() async {
        guard canSave else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            try checkEnvironment()
            let result = if isEditing {
                try await repo.updateSupport(appId: appId, fields: buildUpdate())
            } else {
                try await repo.createSupport(buildSupport())
            }
            draftSession.discard()
            isEditing = true
            populate(from: result)
            draftSession.setBaseline(currentDraft)
            saved = result
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
    
    func delete() async {
        guard isEditing, !isSaving else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            try checkEnvironment()
            try await repo.deleteSupport(appId: appId)
            draftSession.discard()
            deleted = true
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
    
    /// Deletes the draft and goes back to the version the editor opened with.
    func discardDraft() {
        draftSession.discard()
        if let baseline = draftSession.baseline { populate(fromDraft: baseline) }
    }
    
    /// Saves the draft now, when the editor closes or the app goes to the background.
    func saveDraftNow() {
        guard !deleted else { return }
        
        draftSession.save(currentDraft)
    }
    
    // MARK: - Helpers
    
    private func fieldChanged() {
        guard !isPopulating else { return }
        
        draftSession.scheduleSave(currentDraft)
    }
    
    private func checkEnvironment() throws(APIError) {
        guard ServerSettings(userDefaults: userDefaults).activeEnvironment == environment else {
            throw .environmentChanged(openedFrom: environment)
        }
    }
    
    private func populate(from support: AppSupport) {
        isPopulating = true
        defer { isPopulating = false }
        
        appName = support.appName
        version = support.version
        subtitle = support.subtitle
        content = support.content
        contactUrl = support.contactUrl ?? ""
        contactText = support.contactText ?? ""
    }
    
    private func populate(fromDraft draft: AppSupportDraft) {
        isPopulating = true
        defer { isPopulating = false }
        
        appName = draft.appName
        version = draft.version
        subtitle = draft.subtitle
        content = draft.content
        contactUrl = draft.contactUrl
        contactText = draft.contactText
    }
    
    private func buildUpdate() -> AppSupportUpdate {
        AppSupportUpdate(
            appName: appName,
            version: version,
            subtitle: subtitle,
            content: content,
            contactUrl: contactUrl.isEmpty ? nil : contactUrl,
            contactText: contactText.isEmpty ? nil : contactText
        )
    }
    
    private func buildSupport() -> AppSupport {
        AppSupport(
            id: appId,
            appName: appName,
            version: version,
            subtitle: subtitle,
            content: content,
            contactUrl: contactUrl.isEmpty ? nil : contactUrl,
            contactText: contactText.isEmpty ? nil : contactText
        )
    }
}
