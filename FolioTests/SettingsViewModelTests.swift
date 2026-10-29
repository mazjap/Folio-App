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
        vm.save(for: .dev)
        
        #expect(!vm.showsSaved)
        #expect(vm.error == .unexpectedStatus(-25308))
        #expect(keychain.values.isEmpty)
    }
    
    @Test func keySavesToTheEnvironmentsKey() {
        let keychain = TestKeychain()
        let vm = SettingsViewModel(userDefaults: makeUserDefaults(), keychain: keychain)
        vm.prodAPIKey = "prod-secret"
        vm.save(for: .prod)
        
        #expect(vm.showsSaved)
        #expect(keychain.values == [FolioStorageKey.prodApiKey: "prod-secret"])
    }
    
    /// Regression test: base URLs were saved on every keystroke, so a half-typed address became the server Folio sent changes to.
    @Test func baseURLsSaveOnlyWhenSaved() {
        let defaults = makeUserDefaults()
        let vm = SettingsViewModel(userDefaults: defaults, keychain: TestKeychain())
        vm.devBaseURL = "http://localhost:3001/"
        
        #expect(defaults.string(forKey: FolioStorageKey.devBaseURL) == nil)
        #expect(vm.hasChanges(for: .dev))
        
        vm.save(for: .dev)
        
        #expect(defaults.string(forKey: FolioStorageKey.devBaseURL) == "http://localhost:3001")
        #expect(vm.devBaseURL == "http://localhost:3001")
        #expect(!vm.hasChanges(for: .dev))
        #expect(ServerSettings(userDefaults: defaults, keychain: TestKeychain()).baseURLString == "http://localhost:3001")
    }
    
    /// Regression test: any string `URL(string:)` accepted could be saved as a base URL, like one without a scheme, or ending in /api.
    @Test(arguments: [
        ("localhost:3001", ServerURL.Issue.notAURL),
        ("ftp://example.com", .unsupportedScheme),
        ("http://example.com", .insecureHost),
        ("https://example.com/api", .includesAPIPath),
        ("https://example.com?x=1", .hasQueryOrFragment)
    ])
    func invalidBaseURLsAreRefused(url: String, issue: ServerURL.Issue) {
        let defaults = makeUserDefaults()
        let vm = SettingsViewModel(userDefaults: defaults, keychain: TestKeychain())
        vm.prodBaseURL = url
        vm.save(for: .prod)
        
        #expect(vm.baseURLIssue(for: .prod) == issue)
        #expect(defaults.string(forKey: FolioStorageKey.prodBaseURL) == nil)
    }
    
    @Test func savingAnEmptyKeyRemovesIt() {
        let keychain = TestKeychain(values: [FolioStorageKey.devApiKey: "old"])
        let vm = SettingsViewModel(userDefaults: makeUserDefaults(), keychain: keychain)
        vm.devAPIKey = ""
        vm.save(for: .dev)
        
        #expect(keychain.values.isEmpty)
    }
    
    /// Regression test: a Keychain that couldn't be read (like when it's locked) looked the same as having no key saved.
    @Test func unreadableKeychainIsReported() {
        let vm = SettingsViewModel(userDefaults: makeUserDefaults(), keychain: TestKeychain(readError: .unexpectedStatus(-25308)))
        
        #expect(vm.error == .unexpectedStatus(-25308))
    }
}
