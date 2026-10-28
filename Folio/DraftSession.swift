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
    
    /// The key the draft is saved under. Changes when a new item is first saved and gets its ID.
    @ObservationIgnored var key: String
    
    /// What the editor shows when nothing's been changed.
    @ObservationIgnored private(set) var baseline: Draft?
    
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private let store: DraftStore
    @ObservationIgnored private let autosaveDelay: Duration
    
    init(key: String, store: DraftStore = .live, autosaveDelay: Duration = .seconds(2)) {
        self.key = key
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
        guard let baseline, let draft = store.load(Draft.self, key: key) else { return nil }
        
        guard !draft.hasSameContent(as: baseline) else {
            discard()
            return nil
        }
        
        hasDraft = true
        isStale = draft.serverUpdatedAt != baseline.serverUpdatedAt
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
            store.save(draft, key: key)
            hasDraft = true
        }
    }
    
    /// Deletes the saved draft and cancels any scheduled save.
    func discard() {
        autosaveTask?.cancel()
        store.clear(key: key)
        hasDraft = false
        isStale = false
    }
}
