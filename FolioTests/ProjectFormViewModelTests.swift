import Foundation
import Testing
@testable import Folio

@MainActor
@Suite
struct ProjectFormViewModelTests {
    let repo = TestProjectRepository()
    let mediaRepo = TestMediaRepository()
    let drafts = DraftStore.temporary()
    let defaults = makeUserDefaults(environment: .dev)
    let draftKey = ProjectFormViewModel.draftKey(for: .edit(id: ProjectDetail.sample.id), environment: .dev)
    
    func makeViewModel(mode: ProjectFormViewModel.Mode = .edit(id: ProjectDetail.sample.id)) -> ProjectFormViewModel {
        ProjectFormViewModel(mode: mode, repo: repo, mediaRepo: mediaRepo, drafts: drafts, userDefaults: defaults)
    }
    
    // MARK: - Drafts
    
    /// Regression test: opening a project and leaving saved a copy of it as a draft, which hid later changes made on the server.
    @Test func openingAndLeavingDoesNotSaveADraft() async {
        let vm = makeViewModel()
        await vm.load()
        vm.saveDraftNow()
        
        #expect(!drafts.contains(key: draftKey))
    }
    
    /// Regression test: leaving before the project loaded saved a draft with every field empty.
    @Test func leavingBeforeLoadingDoesNotSaveADraft() async {
        repo.fetchError = .networkFailed(URLError(.cancelled))
        let vm = makeViewModel()
        await vm.load()
        vm.saveDraftNow()
        
        #expect(!drafts.contains(key: draftKey))
    }
    
    /// Regression test: gallery changes weren't part of drafts, so they were lost when the editor closed without saving.
    @Test func galleryChangesAreSavedInTheDraft() async {
        let vm = makeViewModel()
        await vm.load()
        vm.media.removeFirst()
        vm.saveDraftNow()
        
        let reopened = makeViewModel()
        await reopened.load()
        
        #expect(reopened.media == Array(ProjectDetail.sample.media.dropFirst()))
    }
    
    /// Regression test: when a project failed to load, the empty form could still be saved, which erased it on the server.
    @Test func projectThatFailedToLoadCannotBeSaved() async {
        repo.fetchError = .networkFailed(URLError(.timedOut))
        let vm = makeViewModel()
        await vm.load()
        vm.title = "Typed after the failure"
        vm.tagline = "Also typed"
        await vm.save()
        
        #expect(!vm.canSave)
        #expect(repo.updates.isEmpty)
    }
    
    /// Regression test: a picked hero image that hadn't been uploaded yet wasn't part of the draft, so it was lost when the editor closed.
    @Test func pickedHeroImageIsSavedInTheDraft() async {
        let vm = makeViewModel()
        await vm.load()
        vm.pendingHeroImage = sampleImage
        vm.saveDraftNow()
        
        let reopened = makeViewModel()
        await reopened.load()
        
        #expect(reopened.pendingHeroImage == sampleImage)
    }
    
    // MARK: - Validation
    
    /// Regression test: a project without a tagline could be saved, and the server rejected it with "Server error (400)".
    @Test func taglineIsRequired() async {
        let vm = makeViewModel(mode: .create)
        await vm.load()
        vm.id = "new-project"
        vm.title = "New Project"
        
        #expect(!vm.canSave)
        #expect(vm.validationIssues == ["Enter a tagline."])
        
        vm.tagline = "One line"
        
        #expect(vm.canSave)
    }
    
    /// Regression test: links accepted any text, and the server rejects anything but full http, https, or mailto URLs.
    @Test func linksMustBeFullURLs() {
        #expect(ProjectFormViewModel.linkIssue(name: "GitHub", url: "github.com/me") != nil)
        #expect(ProjectFormViewModel.linkIssue(name: "GitHub", url: "https://") != nil)
        #expect(ProjectFormViewModel.linkIssue(name: "", url: "https://github.com") != nil)
        #expect(ProjectFormViewModel.linkIssue(name: "GitHub", url: "https://github.com/me") == nil)
        #expect(ProjectFormViewModel.linkIssue(name: "Email", url: "mailto:me@example.com") == nil)
    }
    
    // MARK: - Clearing fields
    
    /// Regression test: clearing the category or hero image left it out of the update, so the server kept the old value.
    @Test func clearingFieldsClearsThemOnTheServer() async {
        let vm = makeViewModel()
        await vm.load()
        vm.category = ""
        vm.heroImage = ""
        await vm.save()
        
        #expect(repo.projects[0].category == nil)
        #expect(repo.projects[0].heroImage == "")
    }
    
    // MARK: - Media
    
    /// Regression test: removing an image from the gallery never deleted its file from the server.
    @Test func removedGalleryImageIsDeletedAfterSaving() async {
        let vm = makeViewModel()
        await vm.load()
        vm.media.removeFirst()
        
        #expect(mediaRepo.deletedFiles.isEmpty)
        
        await vm.save()
        
        #expect(vm.error == nil)
        #expect(mediaRepo.deletedFiles == ["/media/projects/sample-project/one.webp"])
    }
    
    @Test func addingMediaUploadsUnderTheProjectsID() async {
        let vm = makeViewModel()
        await vm.load()
        await vm.addMedia([sampleImage, sampleImage])
        
        #expect(vm.media.count == ProjectDetail.sample.media.count + 2)
        #expect(mediaRepo.uploads.map(\.id) == ["sample-project", "sample-project"])
        #expect(mediaRepo.uploads.allSatisfy { $0.context == .projects })
    }
    
    /// Regression test: a gallery image uploaded and then removed before saving was never deleted from the server.
    @Test func galleryUploadRemovedBeforeSavingIsDeleted() async {
        let vm = makeViewModel()
        await vm.load()
        await vm.addMedia([sampleImage])
        vm.media.removeLast()
        await vm.save()
        
        #expect(mediaRepo.deletedFiles == ["/media/projects/sample-project/upload-1.webp"])
    }
    
    /// Regression test: a new project's gallery accepted uploads before it had an ID, which sent an empty ID to the server.
    @Test func newProjectCannotAddMediaBeforeItHasAnID() async {
        let vm = makeViewModel(mode: .create)
        await vm.load()
        await vm.addMedia([sampleImage])
        
        #expect(!vm.canUploadFiles)
        #expect(vm.media.isEmpty)
        #expect(mediaRepo.uploads.isEmpty)
    }
}
