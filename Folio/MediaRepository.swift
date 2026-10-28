import Foundation

struct MediaUploadResponse: Decodable {
    let url: String
}

// MARK: - Protocol

protocol MediaRepositoryProtocol {
    /// Uploads an image to the item's folder and returns its server-relative path (`/media/<context>/<id>/<name>.webp`).
    func upload(_ image: PendingImage, context: MediaContext, id: String) async throws(APIError) -> String
    func deleteFile(context: MediaContext, id: String, fileName: String) async throws(APIError)
}

extension MediaRepositoryProtocol {
    // MARK: - Functions
    
    /// Deletes the files a save stopped using: paths in `previous` that aren't in `current` and aren't mentioned in `text` (the item's markdown).
    /// Only files in the item's own folder (`/media/<context>/<id>/`) are deleted, and files already gone are ignored.
    func deleteUnusedFiles(previous: [String], current: [String], text: String, context: MediaContext, id: String) async throws(APIError) {
        let folder = "/media/\(context.rawValue)/\(id)/"
        let unused = Set(previous)
            .subtracting(current)
            .filter { $0.hasPrefix(folder) && !text.contains($0) }
        
        for path in unused.sorted() {
            do {
                try await deleteFile(context: context, id: id, fileName: String(path.dropFirst(folder.count)))
            } catch {
                guard case .notFound = error else { throw error }
            }
        }
    }
}

// MARK: - Implementation

struct MediaRepository: MediaRepositoryProtocol {
    func upload(_ image: PendingImage, context: MediaContext, id: String) async throws(APIError) -> String {
        let p = try URLProcessor.fromSettings()
        let data = try await p.upload(
            to: p.apiURL("media", "upload"),
            fileData: image.data,
            fileName: image.uploadFileName,
            mimeType: image.mimeType,
            context: context.rawValue,
            id: id
        )
        return try p.decode(MediaUploadResponse.self, from: data).url
    }
    
    func deleteFile(context: MediaContext, id: String, fileName: String) async throws(APIError) {
        let p = try URLProcessor.fromSettings()
        try await p.delete(p.apiURL("media", context.rawValue, id, fileName))
    }
}

// MARK: - Test fake

/// Records uploads and deletions without a server, for tests and previews.
final class TestMediaRepository: MediaRepositoryProtocol {
    private(set) var uploads: [(context: MediaContext, id: String)] = []
    private(set) var deletedFiles: [String] = []
    var uploadError: APIError?
    
    func upload(_ image: PendingImage, context: MediaContext, id: String) async throws(APIError) -> String {
        if let uploadError { throw uploadError }
        
        uploads.append((context, id))
        return "/media/\(context.rawValue)/\(id)/upload-\(uploads.count).webp"
    }
    
    func deleteFile(context: MediaContext, id: String, fileName: String) async throws(APIError) {
        deletedFiles.append("/media/\(context.rawValue)/\(id)/\(fileName)")
    }
}
