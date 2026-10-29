import Foundation

/// Where an editor is in loading the item it edits.
enum EditorLoadState: Equatable {
    case loading
    /// Loaded from the server, or a new item with nothing to load. Only a loaded item can be saved, so a failed load can never publish empty fields over the server's version.
    case loaded
    /// The server's version couldn't be loaded. `showsDraft` is true when the editor shows the item's saved draft in its place, which can be edited but not saved until it loads.
    case failed(message: String, showsDraft: Bool)
}
