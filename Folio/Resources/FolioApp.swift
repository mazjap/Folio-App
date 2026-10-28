import SwiftUI

@main
struct FolioApp: App {
    /// Unit tests run inside the app, so while testing it shows nothing rather than loading content from the server.
    private let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    
    var body: some Scene {
        WindowGroup {
            if isTesting {
                EmptyView()
            } else {
                ContentView()
            }
        }
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }
}
