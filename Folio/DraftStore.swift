import Foundation

// MARK: - Drafts

/// A snapshot of an editor's fields, saved while the user edits so their work survives quitting.
///
/// Drafts are stored as JSON, so add new properties as optionals: drafts saved before them still decode.
nonisolated protocol EditorDraft: Codable, Equatable {
    /// The server's `updatedAt` for the version the draft was started from, used to tell whether the item changed on the server since. `nil` for new items and items never updated.
    var serverUpdatedAt: Date? { get set }
    var savedAt: Date { get set }
}

extension EditorDraft {
    // MARK: - Functions
    
    /// Whether the two drafts have the same field values, ignoring when they were saved and which version they started from.
    func hasSameContent(as other: Self) -> Bool {
        var copy = self
        copy.serverUpdatedAt = other.serverUpdatedAt
        copy.savedAt = other.savedAt
        return copy == other
    }
}

nonisolated struct PostDraft: EditorDraft {
    var id: String
    var title: String
    var excerpt: String
    var content: String
    var tags: [String]
    var heroImage: String
    var series: String
    var createdAt: Date?
    /// A hero image picked but not uploaded yet.
    var pendingHeroImage: PendingImage?
    /// Files uploaded while editing that the server's version doesn't use yet, deleted again if they're not used when the post is saved.
    var uploadedFiles: [String]?
    var serverUpdatedAt: Date?
    var savedAt: Date
}

nonisolated struct ProjectDraft: EditorDraft {
    var id: String
    var title: String
    var tagline: String
    var category: String
    var status: ProjectStatus
    var featured: Bool
    var description: String
    var heroImage: String
    var techStack: [String]
    var links: [String: String]
    var media: [MediaItem]?
    var createdAt: Date?
    /// A hero image picked but not uploaded yet.
    var pendingHeroImage: PendingImage?
    /// Files uploaded while editing that the server's version doesn't use yet, deleted again if they're not used when the project is saved.
    var uploadedFiles: [String]?
    var serverUpdatedAt: Date?
    var savedAt: Date
}

nonisolated struct AppPrivacyPolicyDraft: EditorDraft {
    var appName: String
    /// `yyyy-MM-dd`, as the server stores it.
    var lastUpdated: String
    var content: String
    var contactUrl: String
    var contactText: String
    var serverUpdatedAt: Date?
    var savedAt: Date
}

nonisolated struct AppSupportDraft: EditorDraft {
    var appName: String
    var version: String
    var subtitle: String
    var content: String
    var contactUrl: String
    var contactText: String
    var serverUpdatedAt: Date?
    var savedAt: Date
}

// MARK: - Store

/// Saves drafts as JSON files, one per key (`prod.post-<id>`, `dev.new-project`, …).
struct DraftStore {
    enum DraftError: Error, LocalizedError {
        case couldNotSave(any Error)
        case couldNotDelete(any Error)
        /// A saved draft couldn't be read. It was moved to `keptAt` (when that worked) so later saves don't overwrite it.
        case unreadable(any Error, keptAt: URL?)
        
        var errorDescription: String? {
            switch self {
            case let .couldNotSave(error):
                "Your draft couldn't be saved on this device, so unpublished changes aren't protected: \(error.localizedDescription)"
            case let .couldNotDelete(error):
                "The draft couldn't be deleted: \(error.localizedDescription)"
            case let .unreadable(error, keptAt):
                if let keptAt {
                    "A saved draft couldn't be read (\(error.localizedDescription)). It was kept as \(keptAt.lastPathComponent) in Folio's drafts folder."
                } else {
                    "A saved draft couldn't be read: \(error.localizedDescription)"
                }
            }
        }
    }
    
    let directory: URL
    
    /// Drafts in Application Support, where the app keeps them.
    static let live = DraftStore(directory: .applicationSupportDirectory.appending(path: "Folio/drafts", directoryHint: .isDirectory))
    
    /// An empty store in a new temporary folder, for tests and previews.
    static func temporary() -> DraftStore {
        DraftStore(directory: .temporaryDirectory.appending(path: "FolioDrafts-\(UUID().uuidString)", directoryHint: .isDirectory))
    }
    
    func save<T: Encodable>(_ draft: T, key: String) throws(DraftError) {
        do {
            let data = try JSONEncoder().encode(draft)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url(for: key), options: .atomic)
        } catch {
            throw .couldNotSave(error)
        }
    }
    
    /// The saved draft, or `nil` if there isn't one. A draft that can't be read is moved aside and reported, rather than treated as missing and later overwritten.
    func load<T: Decodable>(_ type: T.Type, key: String) throws(DraftError) -> T? {
        let url = url(for: key)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        
        do {
            return try JSONDecoder().decode(type, from: Data(contentsOf: url))
        } catch {
            let keptAt = directory.appending(path: "\(key).unreadable-\(Int(Date.now.timeIntervalSince1970)).json")
            let moved = (try? FileManager.default.moveItem(at: url, to: keptAt)) != nil
            throw .unreadable(error, keptAt: moved ? keptAt : nil)
        }
    }
    
    func contains(key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key).path(percentEncoded: false))
    }
    
    /// Deletes the draft. Deleting one that isn't there isn't an error.
    func clear(key: String) throws(DraftError) {
        guard contains(key: key) else { return }
        
        do {
            try FileManager.default.removeItem(at: url(for: key))
        } catch {
            throw .couldNotDelete(error)
        }
    }
    
    private func url(for key: String) -> URL {
        directory.appending(path: "\(key).json")
    }
}

// MARK: - Diff

/// Returns NSRanges in `currentText` for lines that are new or changed relative to `serverText`.
/// Used by MarkdownEditorView to highlight uncommitted edits via NSLayoutManager temporary attributes.
func computeChangedLineRanges(from serverText: String, to currentText: String) -> [NSRange] {
    guard !serverText.isEmpty, !currentText.isEmpty else { return [] }
    
    let serverLines = serverText.components(separatedBy: "\n")
    let currentLines = currentText.components(separatedBy: "\n")
    let diff = currentLines.difference(from: serverLines)
    
    var insertedIndices = Set<Int>()
    for case let .insert(offset, _, _) in diff { insertedIndices.insert(offset) }
    
    var ranges: [NSRange] = []
    var charOffset = 0
    for (i, line) in currentLines.enumerated() {
        let lineLength = line.utf16.count
        if insertedIndices.contains(i) {
            ranges.append(NSRange(location: charOffset, length: lineLength))
        }
        charOffset += lineLength + (i < currentLines.count - 1 ? 1 : 0)
    }
    return ranges
}
