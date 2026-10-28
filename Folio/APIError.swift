import Foundation

enum APIError: Error, LocalizedError {
    case unauthorized
    case notFound
    case conflict
    case httpError(statusCode: Int)
    case encodingFailed(any Error)
    case decodingFailed(any Error)
    case networkFailed(any Error)
    case invalidURL
    
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
        case let .httpError(code):
            return "Server error (\(code))."
        case let .encodingFailed(e):
            return "Failed to encode request: \(e.localizedDescription)"
        case let .decodingFailed(e):
            return "Failed to decode response: \(e.localizedDescription)"
        case let .networkFailed(e):
            return "Network error: \(e.localizedDescription)"
        case .invalidURL:
            return "Invalid base URL — check Settings."
        }
    }
}
