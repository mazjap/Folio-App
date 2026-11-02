import Foundation

/// Saves one editor's draft while the user edits, and only while there's something to save.
///
/// Nothing is saved until the editor sets a baseline (the fields as loaded from the server, or empty for a new item), so a failed or cancelled load never saves empty fields. A draft that matches the baseline is deleted rather than saved, so opening an item and leaving doesn't leave a copy behind that would later hide newer changes on the server.
@Observable
final class DraftSession<Draft: EditorDraft>: DraftKeyed {
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
    @ObservationIgnored private var legacyKey: String?
    
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?
    @ObservationIgnored private let store: DraftStore
    @ObservationIgnored private let autosaveDelay: Duration
    
    /// - Parameter claimsNewDraftSlot: For a new item's editor: `key` is the first of a series of keys (`dev.new-post`, `dev.new-post-2`, …), and the session takes one no other open editor has (see `NewDraftSlots`).
    init(key: String, legacyKey: String? = nil, store: DraftStore = .live, autosaveDelay: Duration = .seconds(2), claimsNewDraftSlot: Bool = false) {
        self.key = key
        self.legacyKey = legacyKey
        self.store = store
        self.autosaveDelay = autosaveDelay
        if claimsNewDraftSlot {
            self.key = NewDraftSlots.claim(base: key, in: store, for: self)
            // NOTE: - A draft from before environments were separate belongs to the first slot only.
            if self.key != key { self.legacyKey = nil }
        }
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

// MARK: - New-item draft slots

/// Something that saves a draft under a key that can change, like a `DraftSession`.
protocol DraftKeyed: AnyObject {
    var key: String { get }
}

/// Which new-item drafts are open in an editor, so two windows creating posts at once each keep their own draft instead of overwriting one.
///
/// The first new post's draft is `dev.new-post`; while that's open, the next new post uses `dev.new-post-2`, and so on. A new editor restores the first saved draft that no other editor has open, so every draft is reached in turn, and otherwise starts in the first free slot. A slot is open while its session exists and still uses that key (a new item's key changes when it's first saved).
enum NewDraftSlots {
    private final class Claim {
        weak var owner: (any DraftKeyed)?
        
        init(_ owner: any DraftKeyed) {
            self.owner = owner
        }
    }
    
    private static var claims: [String: Claim] = [:]
    private static let maxSlots = 50
    
    // MARK: - Functions
    
    /// The key `owner` should save under: `base`, or `base-2`, `base-3`, ….
    static func claim(base: String, in store: DraftStore, for owner: any DraftKeyed) -> String {
        // NOTE: - Claims are per store, so tests with their own temporary stores don't see each other's editors.
        func claimID(_ key: String) -> String {
            store.directory.path(percentEncoded: false) + "|" + key
        }
        
        func isOpen(_ key: String) -> Bool {
            claims[claimID(key)]?.owner?.key == key
        }
        
        let free = (1...maxSlots).map { $0 == 1 ? base : "\(base)-\($0)" }.filter { !isOpen($0) }
        let key = free.first(where: { store.contains(key: $0) }) ?? free.first ?? base
        claims[claimID(key)] = Claim(owner)
        return key
    }
}
