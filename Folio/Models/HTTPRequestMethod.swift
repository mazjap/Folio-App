import Foundation

enum HTTPRequestMethod: String {
    case get = "GET"
    case put = "PUT"
    case post = "POST"
    case delete = "DELETE"
}

extension URLRequest {
    var httpMethodType: HTTPRequestMethod? {
        get {
            self.httpMethod.flatMap(HTTPRequestMethod.init(rawValue:))
        }
        set {
            self.httpMethod = newValue?.rawValue
        }
    }
}
