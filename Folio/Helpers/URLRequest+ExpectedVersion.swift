import Foundation

extension URLRequest {
    /// The header the server compares with the item's current version (`backend/src/lib/versions.ts`).
    static let expectedVersionHeader = "X-Expected-Version"
    
    // MARK: - Functions
    
    /// Sends `version` in whole seconds, like the JSON dates: the server then compares to the second, so it doesn't matter that decoding may have lost the stored milliseconds.
    mutating func setExpectedVersion(_ version: Date?) {
        guard let version else { return }
        
        setValue(version.formatted(.iso8601), forHTTPHeaderField: Self.expectedVersionHeader)
    }
}
