import SwiftUI

@main
struct FolioApp: App {
    /// Unit tests run inside the app, so while testing it shows nothing rather than loading content from the server.
    private let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    
    /// Set when UI tests launch the app with `-ui-testing`: sample content from the test repositories, so the app never reaches a server.
    private let uiTestContent = ProcessInfo.processInfo.arguments.contains(UITestContent.launchArgument) ? UITestContent() : nil
    
    var body: some Scene {
        WindowGroup {
            if let uiTestContent {
                ContentView(
                    postRepo: uiTestContent.postRepo,
                    projectRepo: uiTestContent.projectRepo,
                    mediaRepo: uiTestContent.mediaRepo,
                    appsRepo: uiTestContent.appsRepo,
                    drafts: uiTestContent.drafts,
                    userDefaults: uiTestContent.userDefaults,
                    keychain: uiTestContent.keychain
                )
            } else if isTesting {
                EmptyView()
            } else {
                ContentView()
            }
        }
        #if os(macOS)
        Settings {
            if let uiTestContent {
                SettingsView(vm: SettingsViewModel(userDefaults: uiTestContent.userDefaults, keychain: uiTestContent.keychain))
            } else {
                SettingsView()
            }
        }
        #endif
    }
}

// MARK: - UI testing

/// What the app uses when UI tests launch it: the in-memory test repositories with their sample content, and settings and drafts of its own, emptied at each launch.
struct UITestContent {
    static let launchArgument = "-ui-testing"
    
    let postRepo = TestPostRepository()
    let projectRepo = TestProjectRepository()
    let mediaRepo = TestMediaRepository()
    let appsRepo = TestAppsRepository()
    let drafts = DraftStore.temporary()
    let keychain = TestKeychain()
    let userDefaults: UserDefaults
    
    init() {
        let suiteName = "FolioUITests"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(FolioEnvironment.dev.rawValue, forKey: FolioStorageKey.activeEnvironment)
        userDefaults = defaults
    }
}
