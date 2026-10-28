import Foundation
import Testing
@testable import Folio

@MainActor
@Suite
struct SettingsViewModelTests {
    /// Regression test: Save Key said the key was saved even when the Keychain refused it.
    @Test func failedKeySaveShowsAnError() {
        let keychain = TestKeychain(saveError: .unexpectedStatus(-25308))
        let vm = SettingsViewModel(userDefaults: makeUserDefaults(), keychain: keychain)
        vm.devAPIKey = "secret"
        vm.saveAPIKey(for: .dev)
        
        #expect(!vm.showsKeySaved)
        #expect(vm.error == .unexpectedStatus(-25308))
        #expect(keychain.values.isEmpty)
    }
    
    @Test func keySavesToTheEnvironmentsKey() {
        let keychain = TestKeychain()
        let vm = SettingsViewModel(userDefaults: makeUserDefaults(), keychain: keychain)
        vm.prodAPIKey = "prod-secret"
        vm.saveAPIKey(for: .prod)
        
        #expect(vm.showsKeySaved)
        #expect(keychain.values == [FolioStorageKey.prodApiKey: "prod-secret"])
    }
    
    @Test func baseURLsSaveAsTheyAreTyped() {
        let defaults = makeUserDefaults()
        let vm = SettingsViewModel(userDefaults: defaults, keychain: TestKeychain())
        vm.devBaseURL = "http://localhost:3001"
        
        #expect(defaults.string(forKey: FolioStorageKey.devBaseURL) == "http://localhost:3001")
        
        defaults.set("prod", forKey: FolioStorageKey.activeEnvironment)
        defaults.set("https://example.com", forKey: FolioStorageKey.prodBaseURL)
        
        #expect(ServerSettings(userDefaults: defaults, keychain: TestKeychain()).baseURLString == "https://example.com")
    }
}
