import Foundation

enum Secrets {
    private enum Key: String {
        case portfolioApiKey = "PORTFOLIO_API_KEY"
        case portfolioUrl = "PORTFOLIO_URL"
    }
    
    static let portfolioApiKey: String = {
        guard let info = Bundle.main.infoDictionary,
              let value = info[Key.portfolioApiKey.rawValue] as? String else {
            return ""
        }
        return value
    }()

    static let portfolioUrl: String = {
        guard let info = Bundle.main.infoDictionary,
              let value = info[Key.portfolioUrl.rawValue] as? String else {
            return ""
        }
        return value
    }()
}
