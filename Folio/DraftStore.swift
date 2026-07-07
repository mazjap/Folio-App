import Foundation

struct PostDraft: Codable {
    var id: String
    var title: String
    var excerpt: String
    var content: String
    var tags: [String]
    var heroImage: String
    var series: String
    var savedAt: Date
}

struct ProjectDraft: Codable {
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
    var savedAt: Date
}

// Returns NSRanges in `currentText` for lines that are new or changed relative to `serverText`.
// Used by MarkdownEditorView to highlight uncommitted edits via NSLayoutManager temporary attributes.
func computeChangedLineRanges(from serverText: String, to currentText: String) -> [NSRange] {
    guard !serverText.isEmpty, !currentText.isEmpty else { return [] }
    let serverLines = serverText.components(separatedBy: "\n")
    let currentLines = currentText.components(separatedBy: "\n")
    let diff = currentLines.difference(from: serverLines)
    var insertedIndices = Set<Int>()
    for case .insert(let offset, _, _) in diff { insertedIndices.insert(offset) }
    var ranges: [NSRange] = []
    var charOffset = 0
    for (i, line) in currentLines.enumerated() {
        let lineLen = line.utf16.count
        if insertedIndices.contains(i) {
            ranges.append(NSRange(location: charOffset, length: lineLen))
        }
        charOffset += lineLen + (i < currentLines.count - 1 ? 1 : 0)
    }
    return ranges
}

enum DraftStore {
    static func save<T: Encodable>(_ draft: T, key: String) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        try? data.write(to: url(for: key), options: .atomic)
    }

    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func clear(key: String) {
        try? FileManager.default.removeItem(at: url(for: key))
    }

    private static func url(for key: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Folio/drafts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(key).json")
    }
}
