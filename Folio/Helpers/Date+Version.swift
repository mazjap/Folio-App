import Foundation

extension Date {
    // MARK: - Functions
    
    /// Whether two item versions are the same as the server judges them when a client sends whole seconds: compared to the second. The test repositories use it to refuse writes the way the server does.
    func isSameVersion(as other: Date) -> Bool {
        floor(timeIntervalSince1970) == floor(other.timeIntervalSince1970)
    }
}
