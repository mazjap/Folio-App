import Foundation

struct URLProcessor {
    let baseURL: URL
    let apiKey: String

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
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
            (data, response) = try await URLSession.shared.data(for: request)
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

// MARK: - SettingsStore convenience

extension URLProcessor {
    static func fromSettings() throws(APIError) -> URLProcessor {
        let urlString = UserDefaults.standard.string(forKey: FolioStorageKey.baseURL) ?? ""
        guard !urlString.isEmpty, let url = URL(string: urlString) else {
            throw .invalidURL
        }
        let apiKey = KeychainService.read(key: FolioStorageKey.apiKey) ?? ""
        return URLProcessor(baseURL: url, apiKey: apiKey)
    }

    // Turns a server-relative path like "/media/posts/img.jpg" into an absolute URL string.
    func absoluteString(for path: String) -> String {
        let base = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.hasPrefix("/") ? base + path : path
    }
}

// Resolves a server-relative path to a full URL using the base URL stored in settings.
// Returns nil for empty paths; passes through already-absolute URLs unchanged.
func mediaURL(for path: String) -> URL? {
    guard !path.isEmpty else { return nil }
    if let url = URL(string: path), url.scheme != nil { return url }
    let base = UserDefaults.standard.string(forKey: FolioStorageKey.baseURL) ?? ""
    let trimmedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let trimmedPath = path.hasPrefix("/") ? path : "/\(path)"
    return URL(string: trimmedBase + trimmedPath)
}

// Rewrites ![alt](/relative/path) image references in markdown to use the full base URL,
// so StructuredText (Textual) can load them. Already-absolute URLs pass through unchanged.
func resolveMarkdownImageURLs(_ content: String) -> String {
    let base = UserDefaults.standard.string(forKey: FolioStorageKey.baseURL) ?? ""
    guard !base.isEmpty else { return content }
    let trimmedBase = base.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let regex = try? NSRegularExpression(pattern: #"!\[([^\]]*)\]\((/[^)]*)\)"#) else { return content }
    let range = NSRange(content.startIndex..., in: content)
    return regex.stringByReplacingMatches(in: content, range: range, withTemplate: "![$1](\(trimmedBase)$2)")
}
