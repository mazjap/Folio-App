import Foundation
@testable import Folio

/// A small image to upload in tests.
let sampleImage = PendingImage(data: Data([0xFF, 0xD8, 0xFF]), mimeType: "image/jpeg", ext: "jpg")

/// A user defaults domain of its own, so tests don't read or change the app's settings.
func makeUserDefaults() -> UserDefaults {
    let suiteName = "FolioTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

/// Answers every request made through `session` with `handler`'s status code and body, recording the requests.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (URLRequest) -> (statusCode: Int, body: Data) = { _ in (200, Data()) }
    nonisolated(unsafe) static var requests: [URLRequest] = []
    
    static var session: URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
    
    override class func canInit(with request: URLRequest) -> Bool { true }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    
    override func startLoading() {
        Self.requests.append(request)
        let (statusCode, body) = Self.handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    
    override func stopLoading() {}
}
