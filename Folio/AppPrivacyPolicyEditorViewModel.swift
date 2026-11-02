import Foundation

@Observable
class AppPrivacyPolicyEditorViewModel {
    let appId: String
    /// Whether the policy exists on the server, so saving updates it rather than creating it.
    private(set) var isEditing: Bool
    
    /// The environment the editor was opened from. Saves and deletes go only to its server.
    let environment: FolioEnvironment
    
    // MARK: - Form fields
    // Each change schedules a draft save.
    
    var appName = ""        { didSet { fieldChanged() } }
    /// Midnight UTC on the policy's date. The picker shows it in UTC, so the day picked is the day saved wherever the device is.
    var lastUpdated = Date.now.calendarDay() { didSet { fieldChanged() } }
    var content = ""        { didSet { fieldChanged() } }
    var contactUrl = ""     { didSet { fieldChanged() } }
    var contactText = ""    { didSet { fieldChanged() } }
    var pendingAction: EditorAction?
    
    var isSaving = false
    var error: (any LocalizedError)?
    var saved: AppPrivacyPolicy?
    var deleted = false
    
    let draftSession: DraftSession<AppPrivacyPolicyDraft>
    
    @ObservationIgnored private let repo: any AppsRepositoryProtocol
    @ObservationIgnored private let userDefaults: UserDefaults
    @ObservationIgnored private var isPopulating = false
    /// The server's `updatedAt` for the version being edited: sent with saves and deletes so the server can refuse them if the page changed since, and recorded in drafts.
    @ObservationIgnored private var serverUpdatedAt: Date?
    
    static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .gmt
        return df
    }()
    
    // MARK: - Init
    
    init(appId: String, existing: AppPrivacyPolicy?, repo: any AppsRepositoryProtocol = AppsRepository(), drafts: DraftStore = .live, userDefaults: UserDefaults = .standard) {
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
            ContentRules.lengthIssue("The policy", content, max: ContentRules.maxMarkdownLength),
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
    
    /// Whether the restored draft was started from an older version of the page than the server's. Cleared once the user decides what to do with it.
    var isDraftStale: Bool {
        get { draftSession.isStale }
        set { draftSession.isStale = newValue }
    }
    
    static func draftKey(appId: String, environment: FolioEnvironment) -> String {
        "\(environment.rawValue).app-\(appId)-privacy-policy"
    }
    
    private var currentDraft: AppPrivacyPolicyDraft {
        AppPrivacyPolicyDraft(appName: appName, lastUpdated: Self.dateFormatter.string(from: lastUpdated), content: content, contactUrl: contactUrl, contactText: contactText, serverUpdatedAt: serverUpdatedAt, savedAt: .now)
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
                try await repo.updatePrivacyPolicy(appId: appId, fields: buildUpdate(), expectedVersion: serverUpdatedAt)
            } else {
                try await repo.createPrivacyPolicy(buildPolicy())
            }
            draftSession.discard()
            isEditing = true
            populate(from: result)
            draftSession.setBaseline(currentDraft)
            saved = result
        } catch {
            if error.isVersionConflict {
                await reloadAfterConflict(error)
            } else if !error.isCancellation {
                self.error = error
            }
        }
    }
    
    func delete() async {
        guard isEditing, !isSaving else { return }
        
        isSaving = true
        defer { isSaving = false }
        
        do {
            try checkEnvironment()
            try await repo.deletePrivacyPolicy(appId: appId, expectedVersion: serverUpdatedAt)
            draftSession.discard()
            deleted = true
        } catch {
            if error.isVersionConflict {
                await reloadAfterConflict(error)
            } else if !error.isCancellation {
                self.error = error
            }
        }
    }
    
    /// Deletes the draft and goes back to the version the editor opened with.
    func discardDraft() {
        draftSession.discard()
        if let baseline = draftSession.baseline { populate(fromDraft: baseline) }
    }
    
    /// Keeps a draft that was started from an older version of the page.
    func keepStaleDraft() {
        draftSession.isStale = false
        draftSession.save(currentDraft)
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
    
    /// The page changed on the server after the editor opened, so a save or delete was refused. Keeps the edits as a draft and loads the current version as the new baseline, which asks whether to keep the draft over it (`isDraftStale`). If there were no edits to keep, says what happened instead.
    private func reloadAfterConflict(_ conflict: APIError) async {
        draftSession.save(currentDraft)
        do {
            let current = try await repo.fetchPrivacyPolicy(appId: appId)
            populate(from: current)
            draftSession.setBaseline(currentDraft)
            if let draft = draftSession.restore() { populate(fromDraft: draft) }
            if !isDraftStale { error = conflict }
        } catch {
            if !error.isCancellation { self.error = error }
        }
    }
    
    private func checkEnvironment() throws(APIError) {
        guard ServerSettings(userDefaults: userDefaults).activeEnvironment == environment else {
            throw .environmentChanged(openedFrom: environment)
        }
    }
    
    private func populate(from policy: AppPrivacyPolicy) {
        isPopulating = true
        defer { isPopulating = false }
        
        serverUpdatedAt = policy.updatedAt
        appName = policy.appName
        lastUpdated = Self.dateFormatter.date(from: policy.lastUpdated) ?? Date.now.calendarDay()
        content = policy.content
        contactUrl = policy.contactUrl ?? ""
        contactText = policy.contactText ?? ""
    }
    
    private func populate(fromDraft draft: AppPrivacyPolicyDraft) {
        isPopulating = true
        defer { isPopulating = false }
        
        appName = draft.appName
        lastUpdated = Self.dateFormatter.date(from: draft.lastUpdated) ?? lastUpdated
        content = draft.content
        contactUrl = draft.contactUrl
        contactText = draft.contactText
    }
    
    private func buildUpdate() -> AppPrivacyPolicyUpdate {
        AppPrivacyPolicyUpdate(
            appName: appName,
            lastUpdated: Self.dateFormatter.string(from: lastUpdated),
            content: content,
            contactUrl: contactUrl.isEmpty ? nil : contactUrl,
            contactText: contactText.isEmpty ? nil : contactText
        )
    }
    
    private func buildPolicy() -> AppPrivacyPolicy {
        AppPrivacyPolicy(
            id: appId,
            appName: appName,
            lastUpdated: Self.dateFormatter.string(from: lastUpdated),
            content: content,
            contactUrl: contactUrl.isEmpty ? nil : contactUrl,
            contactText: contactText.isEmpty ? nil : contactText
        )
    }
}
