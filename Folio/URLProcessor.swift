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
            throw .httpError(statusCode: -1, message: nil)
        }
        
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw .unauthorized
        case 404: throw .notFound
        case 409: throw .conflict
        default: throw .httpError(statusCode: http.statusCode, message: Self.serverMessage(in: data))
        }
    }
    
    /// The `error` text of a JSON error response (`{ "error": "tagline can't be empty" }`), shortened if it's very long. `nil` when the body isn't one.
    static func serverMessage(in data: Data) -> String? {
        struct ErrorBody: Decodable {
            let error: String
        }
        
        guard let message = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error.trimmingCharacters(in: .whitespacesAndNewlines),
              !message.isEmpty
        else { return nil }
        
        return message.count > 500 ? String(message.prefix(500)) + "…" : message
    }
}

// MARK: - Settings

extension URLProcessor {
    static func fromSettings(_ settings: ServerSettings = ServerSettings()) throws(APIError) -> URLProcessor {
        guard case let .success(urlString) = ServerURL.normalize(settings.baseURLString),
              let url = URL(string: urlString)
        else {
            throw .invalidURL
        }
        
        do {
            return URLProcessor(baseURL: url, apiKey: try settings.apiKey())
        } catch {
            throw .keychain(error)
        }
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

/// The path of a smaller copy of an uploaded image, which the server saves beside it (`/media/…/hero.webp` → `/media/…/hero.w640.webp`), or `nil` for paths that don't have one (anything but a server `.webp`).
///
/// Images uploaded before the server made smaller copies don't have them until it backfills them, so fall back to `path` if this doesn't load.
func smallerMediaPath(for path: String, width: Int) -> String? {
    guard path.hasPrefix("/media/"), path.hasSuffix(".webp"), path.range(of: #"\.w\d+\.webp$"#, options: .regularExpression) == nil else { return nil }
    
    return String(path.dropLast(".webp".count)) + ".w\(width).webp"
}

/// Rewrites relative image references in markdown (`![alt](/media/…)` and reference definitions like `[hero]: /media/…`) to use the full base URL, so StructuredText (Textual) can load them.
///
/// Already-absolute URLs pass through unchanged, as does anything inside fenced code blocks or inline code, which shows markdown rather than rendering it.
func resolveMarkdownImageURLs(_ content: String, baseURL: String = ServerSettings().baseURLString) -> String {
    guard !baseURL.isEmpty,
          let inlineImage = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\((/[^/)][^)]*)\)"#),
          let referenceDefinition = try? NSRegularExpression(pattern: #"^( {0,3}\[[^\]]+\]:[ \t]*)(/[^/\s]\S*)"#)
    else { return content }
    
    let base = NSRegularExpression.escapedTemplate(for: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
    
    func replacing(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
    
    var openFence: String?
    let lines = content.components(separatedBy: "\n").map { line -> String in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if let fence = openFence {
            if trimmed.hasPrefix(fence) { openFence = nil }
            return line
        }
        if let fence = ["```", "~~~"].first(where: trimmed.hasPrefix) {
            openFence = fence
            return line
        }
        
        let resolvedDefinition = replacing(referenceDefinition, in: line, with: "$1\(base)$2")
        // NOTE: - Splitting on backticks leaves inline code at the odd-numbered pieces.
        return resolvedDefinition
            .components(separatedBy: "`")
            .enumerated()
            .map { index, piece in index.isMultiple(of: 2) ? replacing(inlineImage, in: piece, with: "![$1](\(base)$2)") : piece }
            .joined(separator: "`")
    }
    return lines.joined(separator: "\n")
}
