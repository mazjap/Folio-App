import Foundation
import Testing
@testable import Folio

@MainActor
@Suite
struct PostEditorViewModelTests {
    let repo = TestPostRepository()
    let mediaRepo = TestMediaRepository()
    let drafts = DraftStore.temporary()
    let draftKey = PostEditorViewModel.draftKey(for: .edit(id: PostDetail.sample.id))
    
    func makeViewModel(mode: PostEditorViewModel.Mode = .edit(id: PostDetail.sample.id)) -> PostEditorViewModel {
        PostEditorViewModel(mode: mode, repo: repo, mediaRepo: mediaRepo, drafts: drafts)
    }
    
    // MARK: - Drafts
    
    /// Regression test: opening a post and leaving saved a copy of it as a draft, which hid later changes made on the server.
    @Test func openingAndLeavingDoesNotSaveADraft() async {
        let vm = makeViewModel()
        await vm.load()
        vm.saveDraftNow()
        
        #expect(!vm.hasDraft)
        #expect(!drafts.contains(key: draftKey))
    }
    
    /// Regression test: leaving before the post loaded saved a draft with every field empty, which blanked the post the next time it opened.
    @Test func leavingBeforeLoadingDoesNotSaveADraft() async {
        repo.fetchError = .networkFailed(URLError(.cancelled))
        let vm = makeViewModel()
        await vm.load()
        vm.saveDraftNow()
        
        #expect(!drafts.contains(key: draftKey))
        #expect(vm.error == nil)
    }
    
    @Test func editsAreSavedAndRestored() async {
        let vm = makeViewModel()
        await vm.load()
        vm.title = "Edited"
        vm.saveDraftNow()
        
        let reopened = makeViewModel()
        await reopened.load()
        
        #expect(reopened.title == "Edited")
        #expect(reopened.content == PostDetail.sample.content)
        #expect(reopened.hasDraft)
        #expect(!reopened.isDraftStale)
    }
    
    @Test func undoingEditsDeletesTheDraft() async {
        let vm = makeViewModel()
        await vm.load()
        vm.title = "Edited"
        vm.saveDraftNow()
        vm.title = PostDetail.sample.title
        vm.saveDraftNow()
        
        #expect(!vm.hasDraft)
        #expect(!drafts.contains(key: draftKey))
    }
    
    /// Regression test: a draft saved by an earlier version (with no server version recorded) that matched the server kept showing Discard Draft.
    @Test func unchangedDraftFromBeforeTheFixIsDeleted() async {
        let old = PostDetail.sample
        drafts.save(
            PostDraft(id: old.id, title: old.title, excerpt: old.excerpt, content: old.content, tags: old.tags, heroImage: old.heroImage ?? "", series: old.series ?? "", createdAt: old.createdAt, serverUpdatedAt: nil, savedAt: .sampleDate),
            key: draftKey
        )
        
        let vm = makeViewModel()
        await vm.load()
        
        #expect(!vm.hasDraft)
        #expect(!drafts.contains(key: draftKey))
    }
    
    @Test func draftStartedFromAnOlderVersionIsStale() async {
        let vm = makeViewModel()
        await vm.load()
        vm.title = "Edited here"
        vm.saveDraftNow()
        
        repo.posts[0].content = "Edited on the website"
        repo.posts[0].updatedAt = .sampleDate.addingTimeInterval(60)
        
        let reopened = makeViewModel()
        await reopened.load()
        
        #expect(reopened.isDraftStale)
        #expect(reopened.title == "Edited here")
        
        reopened.discardDraft()
        
        #expect(reopened.title == PostDetail.sample.title)
        #expect(reopened.content == "Edited on the website")
        #expect(!drafts.contains(key: draftKey))
    }
    
    /// Regression test: leaving a post right after publishing it saved a draft of what was just published.
    @Test func publishingDeletesTheDraftAndLeavingDoesNotSaveAnother() async {
        let vm = makeViewModel()
        await vm.load()
        vm.title = "Edited"
        vm.saveDraftNow()
        await vm.save()
        vm.saveDraftNow()
        
        #expect(vm.error == nil)
        #expect(!vm.hasDraft)
        #expect(!drafts.contains(key: draftKey))
    }
    
    @Test func creatingAPostMovesToEditMode() async {
        let vm = makeViewModel(mode: .create)
        await vm.load()
        vm.id = "New Post!"
        vm.title = "New Post"
        vm.saveDraftNow()
        await vm.save()
        vm.saveDraftNow()
        
        #expect(vm.mode == .edit(id: "new-post"))
        #expect(repo.posts.contains { $0.id == "new-post" })
        #expect(!drafts.contains(key: PostEditorViewModel.draftKey(for: .create)))
        #expect(!drafts.contains(key: PostEditorViewModel.draftKey(for: .edit(id: "new-post"))))
    }
    
    // MARK: - Clearing fields
    
    /// Regression test: clearing the hero image or series left it out of the update, so the server kept the old value.
    @Test func clearingOptionalFieldsClearsThemOnTheServer() async {
        let vm = makeViewModel()
        await vm.load()
        vm.heroImage = ""
        vm.series = ""
        await vm.save()
        
        #expect(repo.updates.last?.fields.heroImage == nil)
        #expect(repo.updates.last?.fields.series == nil)
        #expect(repo.posts[0].heroImage == nil)
        #expect(repo.posts[0].series == nil)
    }
    
    // MARK: - Media
    
    @Test func replacingTheHeroImageDeletesTheOldFile() async {
        let vm = makeViewModel()
        await vm.load()
        vm.pendingHeroImage = sampleImage
        await vm.save()
        
        #expect(vm.error == nil)
        #expect(mediaRepo.deletedFiles == ["/media/posts/sample-post/hero.webp"])
    }
    
    @Test func heroImageStillUsedInTheContentIsKept() async {
        let vm = makeViewModel()
        await vm.load()
        vm.content += "\n\n![](/media/posts/sample-post/hero.webp)"
        vm.heroImage = ""
        await vm.save()
        
        #expect(mediaRepo.deletedFiles.isEmpty)
    }
    
    /// Regression test: a new post's images could be uploaded before it had an ID, under an empty one.
    @Test func newPostCannotUploadBeforeItHasAnID() async {
        let vm = makeViewModel(mode: .create)
        await vm.load()
        
        #expect(!vm.canUploadFiles)
        
        await vm.uploadInlineImage(sampleImage)
        
        #expect(mediaRepo.uploads.isEmpty)
        #expect(vm.pendingAction == nil)
    }
    
    @Test func uploadingLocksANewPostsID() async {
        let vm = makeViewModel(mode: .create)
        await vm.load()
        vm.id = "my post"
        await vm.uploadInlineImage(sampleImage)
        
        #expect(vm.hasUploadedFiles)
        #expect(mediaRepo.uploads.first?.id == "my-post")
    }
}
