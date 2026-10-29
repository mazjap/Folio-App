import Foundation

/// Saves one editor's draft while the user edits, and only while there's something to save.
///
/// Nothing is saved until the editor sets a baseline (the fields as loaded from the server, or empty for a new item), so a failed or cancelled load never saves empty fields. A draft that matches the baseline is deleted rather than saved, so opening an item and leaving doesn't leave a copy behind that would later hide newer changes on the server.
@Observable
final class DraftSession<Draft: EditorDraft> {
    /// Whether a draft with unpublished changes is saved for this item.
    private(set) var hasDraft = false
    
    /// Whether the restored draft was started from an older version than the server's, so publishing it would undo the server's newer changes. Set to false once the user has decided to keep it.
    var isStale = false
    
    /// Whether the restored draft was saved before drafts were kept apart by environment, so it may have been started on the other server. Shown with `isStale`.
    private(set) var isLegacy = false
    
    /// Whether the last save failed, so the editor's changes aren't protected on disk.
    private(set) var isFailing = false
    
    /// Called when the draft can't be saved, read, or deleted, for the editor to show.
    @ObservationIgnored var onError: ((DraftStore.DraftError) -> Void)?
    
    /// The key the draft is saved under. Changes when a new item is first saved and gets its ID.
    @ObservationIgnored var key: String
    
    /// What the editor shows when nothing's been changed.
    @ObservationIgnored private(set) var baseline: Draft?
    
    /// Where the draft was saved before drafts were kept apart by environment. Restored once, then moved to `key`.
    @ObservationIgnored private let legacyKey: String?
    
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private let store: DraftStore
    @ObservationIgnored private let autosaveDelay: Duration
    
    init(key: String, legacyKey: String? = nil, store: DraftStore = .live, autosaveDelay: Duration = .seconds(2)) {
        self.key = key
        self.legacyKey = legacyKey
        self.store = store
        self.autosaveDelay = autosaveDelay
    }
    
    // MARK: - Functions
    
    /// Sets what the editor shows when nothing's been changed, and cancels any save scheduled before it.
    func setBaseline(_ draft: Draft) {
        autosaveTask?.cancel()
        baseline = draft
    }
    
    /// Loads the saved draft if it has changes from the baseline, and deletes it if it doesn't. Call after `setBaseline(_:)`.
    func restore() -> Draft? {
        guard let baseline, let loaded = loadDraft() else { return nil }
        
        let (draft, isLegacy) = loaded
        
        guard !draft.hasSameContent(as: baseline) else {
            discard()
            return nil
        }
        
        hasDraft = true
        self.isLegacy = isLegacy
        // NOTE: - A draft from before environments were separate might belong to the other server, so the user decides whether to keep it, as with a stale one.
        isStale = isLegacy || draft.serverUpdatedAt != baseline.serverUpdatedAt
        return draft
    }
    
    /// Loads the saved draft when the server's version couldn't be loaded, so the user can keep working on it offline.
    ///
    /// `empty` becomes the baseline, so edits keep being saved over the draft. Call `restore()` once the server's version loads, after saving the draft.
    func restoreOffline(empty: Draft) -> Draft? {
        guard let loaded = loadDraft() else { return nil }
        
        let (draft, isLegacy) = loaded
        
        baseline = empty
        hasDraft = true
        self.isLegacy = isLegacy
        return draft
    }
    
    /// Saves `draft` after a pause, replacing any save scheduled before it.
    func scheduleSave(_ draft: Draft) {
        guard baseline != nil else { return }
        
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self, autosaveDelay] in
            try? await Task.sleep(for: autosaveDelay)
            guard !Task.isCancelled else { return }
            
            self?.save(draft)
        }
    }
    
    /// Saves `draft` now, or deletes the saved draft if `draft` matches the baseline. Does nothing before a baseline is set.
    func save(_ draft: Draft) {
        autosaveTask?.cancel()
        guard let baseline else { return }
        
        if draft.hasSameContent(as: baseline) {
            discard()
        } else {
            var draft = draft
            draft.savedAt = .now
            do {
                try store.save(draft, key: key)
                hasDraft = true
                isFailing = false
            } catch {
                report(error)
            }
        }
    }
    
    /// Deletes the saved draft and cancels any scheduled save.
    func discard() {
        autosaveTask?.cancel()
        do {
            try store.clear(key: key)
            hasDraft = false
            isStale = false
            isLegacy = false
            isFailing = false
        } catch {
            report(error)
        }
    }
    
    // MARK: - Helpers
    
    /// The draft saved under `key`, or else under `legacyKey`, which is moved to `key`.
    private func loadDraft() -> (Draft, isLegacy: Bool)? {
        do {
            if let draft = try store.load(Draft.self, key: key) { return (draft, false) }
            
            guard let legacyKey, let draft = try store.load(Draft.self, key: legacyKey) else { return nil }
            
            try store.save(draft, key: key)
            try store.clear(key: legacyKey)
            return (draft, true)
        } catch {
            report(error)
            return nil
        }
    }
    
    private func report(_ error: DraftStore.DraftError) {
        if case .couldNotSave = error { isFailing = true }
        onError?(error)
    }
}
