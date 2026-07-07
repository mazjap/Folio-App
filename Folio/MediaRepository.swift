import Foundation
import UniformTypeIdentifiers

struct PendingImage {
    var data: Data
    var mimeType: String
    var ext: String
}

struct MediaUploadResponse: Decodable {
    let url: String
}

protocol MediaRepositoryProtocol {
    func upload(fileData: Data, fileName: String, mimeType: String, context: MediaContext, id: String) async throws(APIError) -> String
    func deleteFile(context: MediaContext, id: String, fileName: String) async throws(APIError)
}

struct MediaRepository: MediaRepositoryProtocol {
    private func processor() throws(APIError) -> URLProcessor {
        try .fromSettings()
    }

    func upload(fileData: Data, fileName: String, mimeType: String, context: MediaContext, id: String) async throws(APIError) -> String {
        let p = try processor()
        let url = p.baseURL.appending(path: "api").appending(path: "media").appending(path: "upload")
        let data = try await p.upload(to: url, fileData: fileData, fileName: fileName, mimeType: mimeType, context: context.rawValue, id: id)
        let response = try p.decode(MediaUploadResponse.self, from: data)
        return response.url
    }

    func deleteFile(context: MediaContext, id: String, fileName: String) async throws(APIError) {
        let p = try processor()
        let url = p.baseURL
            .appending(path: "api")
            .appending(path: "media")
            .appending(path: context.rawValue)
            .appending(path: id)
            .appending(path: fileName)
        try await p.delete(url)
    }
}
