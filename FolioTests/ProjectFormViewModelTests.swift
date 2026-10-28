import Foundation
import Testing
@testable import Folio

@MainActor
@Suite
struct ProjectFormViewModelTests {
    let repo = TestProjectRepository()
    let mediaRepo = TestMediaRepository()
    let drafts = DraftStore.temporary()
    let draftKey = ProjectFormViewModel.draftKey(for: .edit(id: ProjectDetail.sample.id))
    
    func makeViewModel(mode: ProjectFormViewModel.Mode = .edit(id: ProjectDetail.sample.id)) -> ProjectFormViewModel {
        ProjectFormViewModel(mode: mode, repo: repo, mediaRepo: mediaRepo, drafts: drafts)
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
