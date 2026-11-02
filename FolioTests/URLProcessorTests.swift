import Foundation
import Testing
@testable import Folio

@MainActor
@Suite(.serialized)
struct URLProcessorTests {
    let processor = URLProcessor(baseURL: URL(string: "https://example.com")!, apiKey: "secret", session: StubURLProtocol.session)
    
    init() {
        StubURLProtocol.requests = []
    }
    
    @Test(arguments: [
        (401, APIError.unauthorized),
        (404, .notFound),
        (409, .conflict(message: nil)),
        (500, .httpError(statusCode: 500, message: nil))
    ])
    func statusCodesMapToErrors(statusCode: Int, expected: APIError) async {
        StubURLProtocol.handler = { _ in (statusCode, Data()) }
        
        await #expect {
            _ = try await processor.get(processor.apiURL("posts"))
        } throws: { error in
            (error as? APIError)?.errorDescription == expected.errorDescription
        }
    }
    
    /// Regression test: the server's explanation of a rejected request was thrown away, so every validation failure said "Server error (400)".
    @Test func serverErrorMessagesAreShown() async {
        StubURLProtocol.handler = { _ in (400, Data(#"{"error":"Invalid project: tagline can't be empty"}"#.utf8)) }
        
        await #expect {
            _ = try await processor.post(processor.apiURL("projects"), body: Data("{}".utf8))
        } throws: { error in
            (error as? APIError)?.errorDescription == "Invalid project: tagline can't be empty"
        }
    }
    
    @Test func errorsWithoutAMessageShowTheStatus() async {
        StubURLProtocol.handler = { _ in (502, Data("<html>Bad Gateway</html>".utf8)) }
        
        await #expect {
            _ = try await processor.get(processor.apiURL("posts"))
        } throws: { error in
            (error as? APIError)?.errorDescription == "Server error (502)."
        }
    }
    
    /// Regression test: a base URL without a scheme or host was used for requests.
    @Test func invalidBaseURLsAreNotUsed() {
        let defaults = makeUserDefaults()
        defaults.set("localhost:3001", forKey: FolioStorageKey.devBaseURL)
        
        #expect(throws: APIError.self) {
            try URLProcessor.fromSettings(ServerSettings(userDefaults: defaults, keychain: TestKeychain()))
        }
    }
    
    @Test func onlyChangesSendTheAPIKey() async throws {
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        _ = try await processor.get(processor.apiURL("posts"))
        _ = try await processor.put(processor.apiURL("posts", "a"), body: Data("{}".utf8))
        
        #expect(StubURLProtocol.requests.map(\.httpMethod) == ["GET", "PUT"])
        #expect(StubURLProtocol.requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(StubURLProtocol.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer secret")
    }
    
    @Test func cancelledRequestsAreRecognized() {
        #expect(APIError.networkFailed(URLError(.cancelled)).isCancellation)
        #expect(!APIError.networkFailed(URLError(.timedOut)).isCancellation)
        #expect(!APIError.notFound.isCancellation)
    }
    
    // MARK: - Conflicts and versions
    
    private func putError(status: Int, body: String) async -> APIError? {
        StubURLProtocol.handler = { _ in (status, Data(body.utf8)) }
        do {
            _ = try await processor.put(processor.apiURL("posts", "a"), body: Data("{}".utf8))
            return nil
        } catch {
            return error
        }
    }
    
    /// Regression test: every 409 said "A resource with that ID already exists", even an upload over an existing file, and a save refused because the post changed on the server couldn't be told apart.
    @Test func conflictsAreToldApart() async {
        let stale = await putError(status: 409, body: #"{"error":"This post was changed on the server.","current":{"id":"a"}}"#)
        #expect(stale?.isVersionConflict == true)
        #expect(stale?.errorDescription == "This post was changed on the server.")
        
        let inUse = await putError(status: 409, body: #"{"error":"This file is still used by post \"b\".","usedBy":["post \"b\""]}"#)
        #expect(inUse?.isInUse == true)
        
        let exists = await putError(status: 409, body: #"{"error":"File already exists. Send overwrite: true to replace it."}"#)
        #expect(exists?.errorDescription == "File already exists. Send overwrite: true to replace it.")
        #expect(exists?.isVersionConflict == false)
        #expect(exists?.isInUse == false)
    }
    
    @Test func savesAndDeletesSendTheVersionTheyStartedFrom() async throws {
        StubURLProtocol.handler = { _ in (200, Data("{}".utf8)) }
        // NOTE: - 2026-10-31T18:02:11.482Z: the milliseconds are dropped, and the server compares to the second.
        let version = Date(timeIntervalSince1970: 1_793_469_731.482)
        _ = try await processor.put(processor.apiURL("posts", "a"), body: Data("{}".utf8), expectedVersion: version)
        try await processor.delete(processor.apiURL("posts", "a"), expectedVersion: version)
        _ = try await processor.put(processor.apiURL("posts", "a"), body: Data("{}".utf8))
        
        let headers = StubURLProtocol.requests.map { $0.value(forHTTPHeaderField: "X-Expected-Version") }
        #expect(headers == ["2026-10-31T18:02:11Z", "2026-10-31T18:02:11Z", nil])
    }
}
