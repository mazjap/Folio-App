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
        guard case .networkFailed(let e) = self else { return false }
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
        case .httpError(let code):
            return "Server error (\(code))."
        case .encodingFailed(let e):
            return "Failed to encode request: \(e.localizedDescription)"
        case .decodingFailed(let e):
            return "Failed to decode response: \(e.localizedDescription)"
        case .networkFailed(let e):
            return "Network error: \(e.localizedDescription)"
        case .invalidURL:
            return "Invalid base URL — check Settings."
        }
    }
}
