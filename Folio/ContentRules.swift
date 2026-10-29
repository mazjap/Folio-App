import Foundation

/// The server's rules for content (`backend/src/lib/schemas.ts` and `paths.ts`), checked before saving so a problem is explained before publishing instead of failing on the server.
///
/// > Warning: Keep these in step with the server's schemas.
enum ContentRules {
    static let maxSlugLength = 100
    static let reservedIDs: Set<String> = ["index", "nav"]
    static let maxMarkdownLength = 500_000
    
    enum URLSchemes {
        /// `http` and `https`.
        case web
        /// `http`, `https`, and `mailto`.
        case webOrMail
        
        fileprivate var schemes: Set<String> {
            switch self {
            case .web: ["http", "https"]
            case .webOrMail: ["http", "https", "mailto"]
            }
        }
    }
    
    // MARK: - Functions
    
    /// Why `typed` can't be a new item's ID, or `nil` if it can. `typed` is what the user entered; the ID is its slug.
    /// - Parameter reservesNames: Whether `index` and `nav` are reserved, as they are for projects and posts (whose folders hold `index.json` and `nav.json`) but not app pages.
    static func slugIssue(for typed: String, reservesNames: Bool = true) -> String? {
        let slug = typed.slugified
        if typed.trimmingCharacters(in: .whitespaces).isEmpty { return "Enter a URL slug." }
        if slug.isEmpty { return "The URL slug needs at least one letter or number." }
        if slug.count > maxSlugLength { return "The URL slug can be at most \(maxSlugLength) characters." }
        if reservesNames && reservedIDs.contains(slug) { return "“\(slug)” is reserved and can't be a URL slug." }
        return nil
    }
    
    /// Why a required text field is invalid: empty (or only spaces), or longer than `max`.
    static func requiredTextIssue(_ name: String, _ value: String, max: Int) -> String? {
        if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter a \(name.lowercased())." }
        return lengthIssue(name, value, max: max)
    }
    
    static func lengthIssue(_ name: String, _ value: String, max: Int) -> String? {
        value.count > max ? "\(name) can be at most \(max.formatted()) characters (it's \(value.count.formatted()))." : nil
    }
    
    /// Why a list of strings (tags, technologies) is invalid: too many items, or an empty or too-long item.
    static func listIssue(_ name: String, _ items: [String], maxItems: Int, maxLength: Int) -> String? {
        if items.count > maxItems { return "\(name) can have at most \(maxItems) items." }
        if let item = items.first(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty || $0.count > maxLength }) {
            return item.trimmingCharacters(in: .whitespaces).isEmpty ? "\(name) can't include an empty item." : "“\(item.prefix(30))…” is too long: \(name.lowercased()) can be at most \(maxLength) characters each."
        }
        return nil
    }
    
    /// Whether the server accepts `value` as a link: a site path (`/media/…`) or an absolute URL with one of `schemes`.
    static func isAllowedURL(_ value: String, schemes: URLSchemes) -> Bool {
        guard value.count <= 2000, !value.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return false }
        
        if value.hasPrefix("/") { return !value.hasPrefix("//") }
        
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), schemes.schemes.contains(scheme) else { return false }
        
        return scheme == "mailto" ? !url.absoluteString.dropFirst("mailto:".count).isEmpty : !(url.host() ?? "").isEmpty
    }
    
    /// Why an optional link field is invalid, or `nil` if it's empty or allowed.
    static func optionalURLIssue(_ name: String, _ value: String, schemes: URLSchemes) -> String? {
        guard !value.isEmpty, !isAllowedURL(value, schemes: schemes) else { return nil }
        
        return schemes == .webOrMail
            ? "\(name) must be a full URL starting with https:// or mailto:."
            : "\(name) must be a full URL starting with https://."
    }
}
