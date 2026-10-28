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
    var serverUpdatedAt: Date?
    var savedAt: Date
}

// MARK: - Store

/// Saves drafts as JSON files, one per key (`post-<id>`, `project-new`, …).
struct DraftStore {
    let directory: URL
    
    /// Drafts in Application Support, where the app keeps them.
    static let live = DraftStore(directory: .applicationSupportDirectory.appending(path: "Folio/drafts", directoryHint: .isDirectory))
    
    /// An empty store in a new temporary folder, for tests and previews.
    static func temporary() -> DraftStore {
        DraftStore(directory: .temporaryDirectory.appending(path: "FolioDrafts-\(UUID().uuidString)", directoryHint: .isDirectory))
    }
    
    func save<T: Encodable>(_ draft: T, key: String) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(for: key), options: .atomic)
    }
    
    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        
        return try? JSONDecoder().decode(type, from: data)
    }
    
    func contains(key: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: key).path(percentEncoded: false))
    }
    
    func clear(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
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
