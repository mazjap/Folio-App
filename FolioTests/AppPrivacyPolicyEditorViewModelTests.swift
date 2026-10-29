import Foundation
import Testing
@testable import Folio

@MainActor
@Suite
struct AppPrivacyPolicyEditorViewModelTests {
    let repo = TestAppsRepository(privacyPolicies: [.sampleWithContact])
    let drafts = DraftStore.temporary()
    let defaults = makeUserDefaults(environment: .dev)
    
    func makeViewModel(existing: AppPrivacyPolicy? = .sampleWithContact) -> AppPrivacyPolicyEditorViewModel {
        let vm = AppPrivacyPolicyEditorViewModel(appId: AppPrivacyPolicy.sample.id, existing: existing, repo: repo, drafts: drafts, userDefaults: defaults)
        vm.load()
        return vm
    }
    
    /// Regression test: clearing the contact URL or button title left them out of the update, so the server kept the old ones.
    @Test func clearingContactFieldsClearsThemOnTheServer() async {
        let vm = makeViewModel()
        vm.contactUrl = ""
        vm.contactText = ""
        await vm.save()
        
        #expect(repo.privacyPolicies[AppPrivacyPolicy.sample.id]?.contactUrl == nil)
        #expect(repo.privacyPolicies[AppPrivacyPolicy.sample.id]?.contactText == nil)
    }
    
    /// Regression test: edits to an app page were only kept in memory, so leaving or quitting before saving lost them.
    @Test func editsAreSavedAndRestored() {
        let vm = makeViewModel()
        vm.content = "Edited policy"
        vm.saveDraftNow()
        
        let reopened = makeViewModel()
        
        #expect(reopened.content == "Edited policy")
        #expect(reopened.hasDraft)
    }
    
    @Test func savingDeletesTheDraft() async {
        let vm = makeViewModel()
        vm.content = "Edited policy"
        vm.saveDraftNow()
        await vm.save()
        vm.saveDraftNow()
        
        #expect(vm.saved?.content == "Edited policy")
        #expect(!vm.hasDraft)
    }
    
    /// Regression test: the date was shown in the device's time zone, so in Denver it showed a day early and a picked date was saved a day late.
    @Test func theDateSavedIsTheDateShown() async {
        let vm = makeViewModel()
        
        #expect(AppPrivacyPolicyEditorViewModel.dateFormatter.string(from: vm.lastUpdated) == AppPrivacyPolicy.sample.lastUpdated)
        
        await vm.save()
        
        #expect(repo.privacyPolicyUpdates.last?.fields.lastUpdated == AppPrivacyPolicy.sample.lastUpdated)
    }
    
    @Test func savingAfterSwitchingEnvironmentsIsRefused() async {
        let vm = makeViewModel()
        vm.content = "Edited in Development"
        defaults.set(FolioEnvironment.prod.rawValue, forKey: FolioStorageKey.activeEnvironment)
        await vm.save()
        
        #expect(repo.privacyPolicyUpdates.isEmpty)
        #expect(vm.error != nil)
    }
    
    /// Regression test: the contact URL accepted any text, and the server rejects anything but full http, https, or mailto URLs.
    @Test func contactURLMustBeAFullURL() {
        let vm = makeViewModel()
        vm.contactUrl = "example.com/help"
        
        #expect(!vm.canSave)
        
        vm.contactUrl = "mailto:help@example.com"
        
        #expect(vm.canSave)
    }
}

@MainActor
@Suite
struct AppSupportEditorViewModelTests {
    let repo = TestAppsRepository()
    let drafts = DraftStore.temporary()
    let defaults = makeUserDefaults(environment: .dev)
    
    func makeViewModel() -> AppSupportEditorViewModel {
        let vm = AppSupportEditorViewModel(appId: AppSupport.sample.id, existing: .sample, repo: repo, drafts: drafts, userDefaults: defaults)
        vm.load()
        return vm
    }
    
    /// Regression test: clearing the contact URL or button title left them out of the update, so the server kept the old ones.
    @Test func clearingContactFieldsClearsThemOnTheServer() async {
        let vm = makeViewModel()
        vm.contactUrl = ""
        vm.contactText = ""
        await vm.save()
        
        #expect(repo.supportPages[AppSupport.sample.id]?.contactUrl == nil)
        #expect(repo.supportPages[AppSupport.sample.id]?.contactText == nil)
    }
    
    /// Regression test: edits to an app page were only kept in memory, so leaving or quitting before saving lost them.
    @Test func editsAreSavedAndRestored() {
        let vm = makeViewModel()
        vm.version = "2.0"
        vm.saveDraftNow()
        
        let reopened = makeViewModel()
        
        #expect(reopened.version == "2.0")
        #expect(reopened.hasDraft)
    }
}

extension AppPrivacyPolicy {
    static let sampleWithContact = AppPrivacyPolicy(
        id: AppPrivacyPolicy.sample.id,
        appName: AppPrivacyPolicy.sample.appName,
        lastUpdated: AppPrivacyPolicy.sample.lastUpdated,
        content: AppPrivacyPolicy.sample.content,
        contactUrl: "https://example.com/contact",
        contactText: "Contact Us"
    )
}
