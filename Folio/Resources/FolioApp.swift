import SwiftUI

@main
struct FolioApp: App {
    init() {
        seedDefaultsIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        Settings {
            SettingsView()
        }
        #endif
    }

    private func seedDefaultsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: FolioStorageKey.hasSeeded) else { return }
        UserDefaults.standard.set(Secrets.portfolioUrl, forKey: FolioStorageKey.baseURL)
        try? KeychainService.save(Secrets.portfolioApiKey, key: FolioStorageKey.apiKey)
        UserDefaults.standard.set(true, forKey: FolioStorageKey.hasSeeded)
    }
}
