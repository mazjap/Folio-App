import Foundation

extension String {
    // MARK: - Computed Properties
    
    /// The string as a URL slug: lowercase ASCII letters and digits, with each run of anything else turned into one hyphen (`"My App!"` → `"my-app"`, `"Café Menu"` → `"cafe-menu"`).
    var slugified: String {
        folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }
            .joined(separator: "-")
    }
}
