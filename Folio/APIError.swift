import Foundation

enum APIError: Error, LocalizedError {
    case unauthorized
    case notFound
    case conflict
    /// Any other unsuccessful status, with the server's explanation (its `error` field) when it sent one.
    case httpError(statusCode: Int, message: String?)
    case encodingFailed(any Error)
    case decodingFailed(any Error)
    case networkFailed(any Error)
    case invalidURL
    case keychain(KeychainService.KeychainError)
    /// The editor was opened from a different environment than the active one, so a change would go to the wrong server.
    case environmentChanged(openedFrom: FolioEnvironment)
    /// The item was saved, but files it stopped using couldn't be deleted from the server.
    case cleanupFailed(count: Int, underlying: String)
    
    var isNotFound: Bool {
        if case .notFound = self { true } else { false }
    }
    
    var isCancellation: Bool {
        guard case let .networkFailed(e) = self else { return false }
        return (e as? URLError)?.code == .cancelled
    }
    
    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Unauthorized — check your API key in Settings."
        case .notFound:
            return "The requested resource was not found."
        case .conflict:
            return "A resource with that ID already exists."
        case let .httpError(code, message):
            return message ?? "Server error (\(code))."
        case let .encodingFailed(e):
            return "Failed to encode request: \(e.localizedDescription)"
        case let .decodingFailed(e):
            return "Failed to decode response: \(e.localizedDescription)"
        case let .networkFailed(e):
            return "Network error: \(e.localizedDescription)"
        case .invalidURL:
            return "Invalid base URL — check Settings."
        case let .keychain(e):
            return e.localizedDescription
        case let .environmentChanged(environment):
            return "This was opened from \(environment.longTitle). Switch back to \(environment.longTitle) in Settings to save it, or open it again from the other environment."
        case let .cleanupFailed(count, underlying):
            return "Saved, but \(count == 1 ? "an unused image" : "\(count) unused images") couldn't be deleted from the server (\(underlying)). Folio tries again the next time you save."
        }
    }
}
