import Foundation

struct URLProcessor {
    let baseURL: URL
    let apiKey: String
    var session: URLSession = .shared
    
    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
    
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    
    // MARK: - HTTP methods
    
    func get(_ url: URL) async throws(APIError) -> Data {
        var request = URLRequest(url: url)
        request.httpMethodType = .get
        return try await perform(request)
    }
    
    func post(_ url: URL, body: Data) async throws(APIError) -> Data {
        var request = authorized(url: url, method: .post)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await perform(request)
    }
    
    func put(_ url: URL, body: Data) async throws(APIError) -> Data {
        var request = authorized(url: url, method: .put)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await perform(request)
    }
    
    func delete(_ url: URL) async throws(APIError) {
        _ = try await perform(authorized(url: url, method: .delete))
    }
    
    func upload(to url: URL, fileData: Data, fileName: String, mimeType: String, context: String, id: String, overwrite: Bool = false) async throws(APIError) -> Data {
        var request = authorized(url: url, method: .post)
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(fileData: fileData, fileName: fileName, mimeType: mimeType, context: context, id: id, overwrite: overwrite, boundary: boundary)
        return try await perform(request)
    }
    
    // MARK: - URLs
    
    /// The URL of an API endpoint, like `apiURL("projects", id)` for `<base>/api/projects/<id>`.
    func apiURL(_ components: String...) -> URL {
        components.reduce(baseURL.appending(path: "api")) { $0.appending(path: $1) }
    }
    
    // MARK: - Coding helpers
    
    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(APIError) -> T {
        do {
            return try Self.decoder.decode(type, from: data)
        } catch {
            throw .decodingFailed(error)
        }
    }
    
    func encode<T: Encodable>(_ value: T) throws(APIError) -> Data {
        do {
            return try Self.encoder.encode(value)
        } catch {
            throw .encodingFailed(error)
        }
    }
    
    // MARK: - Private
    
    private func authorized(url: URL, method: HTTPRequestMethod) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethodType = method
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }
    
    private func multipartBody(fileData: Data, fileName: String, mimeType: String, context: String, id: String, overwrite: Bool, boundary: String) -> Data {
        var body = Data()
        
        func append(_ string: String) {
            body.append(contentsOf: string.utf8)
        }
        
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"context\"\r\n\r\n")
        append("\(context)\r\n")
        
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"id\"\r\n\r\n")
        append("\(id)\r\n")
        
        if overwrite {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"overwrite\"\r\n\r\n")
            append("true\r\n")
        }
        
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        append("\r\n--\(boundary)--\r\n")
        
        return body
    }
    
    private func perform(_ request: URLRequest) async throws(APIError) -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .networkFailed(error)
        }
        
        guard let http = response as? HTTPURLResponse else {
            throw .httpError(statusCode: -1)
        }
        
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw .unauthorized
        case 404: throw .notFound
        case 409: throw .conflict
        default: throw .httpError(statusCode: http.statusCode)
        }
    }
}

// MARK: - Settings

extension URLProcessor {
    static func fromSettings(_ settings: ServerSettings = ServerSettings()) throws(APIError) -> URLProcessor {
        let urlString = settings.baseURLString
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            throw .invalidURL
        }
        
        return URLProcessor(baseURL: url, apiKey: settings.apiKey)
    }
}

// MARK: - Media URLs

/// Resolves a server-relative path to a full URL using the active environment's base URL.
/// Returns nil for empty paths; passes through already-absolute URLs unchanged.
func mediaURL(for path: String, baseURL: String = ServerSettings().baseURLString) -> URL? {
    guard !path.isEmpty else { return nil }
    
    if let url = URL(string: path), url.scheme != nil { return url }
    
    let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let trimmedPath = path.hasPrefix("/") ? path : "/\(path)"
    return URL(string: trimmedBase + trimmedPath)
}

/// Rewrites `![alt](/relative/path)` image references in markdown to use the full base URL,
/// so StructuredText (Textual) can load them. Already-absolute URLs pass through unchanged.
func resolveMarkdownImageURLs(_ content: String, baseURL: String = ServerSettings().baseURLString) -> String {
    guard !baseURL.isEmpty,
          let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\((/[^)]*)\)"#)
    else { return content }
    
    let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let range = NSRange(content.startIndex..., in: content)
    let template = "![$1](\(NSRegularExpression.escapedTemplate(for: trimmedBase))$2)"
    return regex.stringByReplacingMatches(in: content, range: range, withTemplate: template)
}
