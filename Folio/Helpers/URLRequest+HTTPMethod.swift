import Foundation

extension URLRequest {
    // MARK: - Computed Properties
    
    var httpMethodType: HTTPRequestMethod? {
        get {
            self.httpMethod.flatMap(HTTPRequestMethod.init(rawValue:))
        }
        set {
            self.httpMethod = newValue?.rawValue
        }
    }
}
