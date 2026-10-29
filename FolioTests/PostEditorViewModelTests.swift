import Foundation
import Testing
@testable import Folio

@MainActor
@Suite
struct PostEditorViewModelTests {
    let repo = TestPostRepository()
    let mediaRepo = TestMediaRepository()
    let drafts = DraftStore.temporary()
    let defaults = makeUserDefaults(environment: .dev)
    let draftKey = PostEditorViewModel.draftKey(for: .edit(id: PostDetail.sample.id), environment: .dev)
    
    func makeViewModel(mode: PostEditorViewModel.Mode = .edit(id: PostDetail.sample.id), drafts: DraftStore? = nil) -> PostEditorViewModel {
        PostEditorViewModel(mode: mode, repo: repo, mediaRepo: mediaRepo, drafts: drafts ?? self.drafts, userDefaults: defaults)
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
    @Test func unchangedDraftFromBeforeTheFixIsDeleted() async throws {
        let old = PostDetail.sample
        try drafts.save(
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
    
    /// Regression test: Development and Production shared draft files, so a draft of a post edited on one server was restored, and could be published, on the other.
    @Test func draftsAreKeptApartByEnvironment() async {
        let vm = makeViewModel()
        await vm.load()
        vm.title = "Edited in Development"
        vm.saveDraftNow()
        
        defaults.set(FolioEnvironment.prod.rawValue, forKey: FolioStorageKey.activeEnvironment)
        let onProduction = makeViewModel()
        await onProduction.load()
        
        #expect(onProduction.title == PostDetail.sample.title)
        #expect(!onProduction.hasDraft)
    }
    
    /// Regression test: a new post's draft was saved as `post-new`, the same file as the draft of a post whose ID is `new`.
    @Test func newPostDraftsDoNotShareAKeyWithAnyPost() {
        #expect(PostEditorViewModel.draftKey(for: .create, environment: .dev) != PostEditorViewModel.draftKey(for: .edit(id: "new"), environment: .dev))
    }
    
    /// Regression test: drafts saved before they were kept apart by environment should still be found, but confirmed, since they may be from the other server.
    @Test func draftFromBeforeEnvironmentsIsRestoredAndConfirmed() async throws {
        let old = PostDetail.sample
        let legacyKey = PostEditorViewModel.legacyDraftKey(for: .edit(id: old.id))
        try drafts.save(
            PostDraft(id: old.id, title: "Old draft", excerpt: old.excerpt, content: old.content, tags: old.tags, heroImage: old.heroImage ?? "", series: old.series ?? "", createdAt: old.createdAt, serverUpdatedAt: old.updatedAt, savedAt: .sampleDate),
            key: legacyKey
        )
        
        let vm = makeViewModel()
        await vm.load()
        
        #expect(vm.title == "Old draft")
        #expect(vm.isDraftStale)
        #expect(vm.isDraftLegacy)
        #expect(!drafts.contains(key: legacyKey))
        #expect(drafts.contains(key: draftKey))
    }
    
    /// Regression test: a draft that couldn't be written to disk was still reported as saved.
    @Test func draftThatCannotBeSavedIsReported() async throws {
        // NOTE: - A file where the drafts folder should be makes every save fail.
        let blocked = FileManager.default.temporaryDirectory.appending(path: "FolioBlocked-\(UUID().uuidString)")
        try Data().write(to: blocked)
        let vm = makeViewModel(drafts: DraftStore(directory: blocked))
        await vm.load()
        vm.title = "Edited"
        vm.saveDraftNow()
        
        #expect(!vm.hasDraft)
        #expect(vm.draftSession.isFailing)
        #expect(vm.error is DraftStore.DraftError)
    }
    
    /// Regression test: a draft that couldn't be read was treated as missing and overwritten by the next autosave.
    @Test func unreadableDraftIsKeptAside() async throws {
        try FileManager.default.createDirectory(at: drafts.directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: drafts.directory.appending(path: "\(draftKey).json"))
        
        let vm = makeViewModel()
        await vm.load()
        
        #expect(vm.error is DraftStore.DraftError)
        #expect(!drafts.contains(key: draftKey))
        let kept = try FileManager.default.contentsOfDirectory(atPath: drafts.directory.path(percentEncoded: false))
        #expect(kept.contains { $0.hasPrefix("\(draftKey).unreadable-") })
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
        #expect(reopened.hasDraft)
    }
    
    /// Regression test: discarding a new post's draft left the publish date the user had picked.
    @Test func discardingANewPostsDraftClearsItsDate() async {
        let vm = makeViewModel(mode: .create)
        await vm.load()
        vm.createdAt = .sampleDate
        vm.discardDraft()
        
        #expect(vm.createdAt == nil)
    }
    
    // MARK: - Loading and saving
    
    /// Regression test: when a post failed to load, the empty form could still be published, which erased the post's content, tags, and hero image on the server.
    @Test func postThatFailedToLoadCannotBePublished() async {
        repo.fetchError = .networkFailed(URLError(.timedOut))
        let vm = makeViewModel()
        await vm.load()
        vm.title = "Typed after the failure"
        await vm.save()
        
        #expect(!vm.canSave)
        #expect(repo.updates.isEmpty)
        #expect(repo.posts[0].content == PostDetail.sample.content)
        guard case .failed(_, showsDraft: false) = vm.loadState else {
            Issue.record("Expected a failed load, got \(vm.loadState)")
            return
        }
    }
    
    /// Regression test: a post with a draft that failed to load (like offline) showed empty fields instead of the draft.
    @Test func draftIsShownWhenThePostCannotLoad() async {
        let vm = makeViewModel()
        await vm.load()
        vm.title = "Edited offline"
        vm.saveDraftNow()
        
        repo.fetchError = .networkFailed(URLError(.notConnectedToInternet))
        let offline = makeViewModel()
        await offline.load()
        
        #expect(offline.title == "Edited offline")
        #expect(offline.loadState == .failed(message: APIError.networkFailed(URLError(.notConnectedToInternet)).localizedDescription, showsDraft: true))
        #expect(!offline.canSave)
        
        offline.excerpt = "Also edited offline"
        repo.fetchError = nil
        await offline.load()
        
        #expect(offline.loadState == .loaded)
        #expect(offline.title == "Edited offline")
        #expect(offline.excerpt == "Also edited offline")
        #expect(offline.hasDraft)
        #expect(offline.canSave)
    }
    
    /// Regression test: text typed while a post was publishing was replaced by the published version and lost.
    @Test func editsMadeWhilePublishingAreKept() async {
        let gate = Gate()
        repo.beforeWrite = { await gate.wait() }
        let vm = makeViewModel()
        await vm.load()
        vm.title = "Published title"
        
        let saving = Task { await vm.save() }
        await gate.untilArrived()
        vm.content = "Typed while publishing"
        gate.open()
        await saving.value
        
        #expect(repo.posts[0].title == "Published title")
        #expect(repo.posts[0].content == PostDetail.sample.content)
        #expect(vm.title == "Published title")
        #expect(vm.content == "Typed while publishing")
        #expect(vm.hasDraft)
    }
    
    /// Regression test: Publish ran a second time while the first was still saving.
    @Test func publishingTwiceAtOnceSavesOnce() async {
        let gate = Gate()
        repo.beforeWrite = { await gate.wait() }
        let vm = makeViewModel()
        await vm.load()
        vm.title = "Edited"
        
        let first = Task { await vm.save() }
        await gate.untilArrived()
        await vm.save()
        gate.open()
        await first.value
        
        #expect(repo.updates.count == 1)
    }
    
    /// Regression test: switching to the other environment while a post was open sent its changes to the other server.
    @Test func publishingAfterSwitchingEnvironmentsIsRefused() async {
        let vm = makeViewModel()
        await vm.load()
        vm.title = "Edited in Development"
        defaults.set(FolioEnvironment.prod.rawValue, forKey: FolioStorageKey.activeEnvironment)
        await vm.save()
        
        #expect(repo.updates.isEmpty)
        guard case .environmentChanged(openedFrom: .dev)? = vm.error as? APIError else {
            Issue.record("Expected an environment error, got \(String(describing: vm.error))")
            return
        }
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
        #expect(!drafts.contains(key: PostEditorViewModel.draftKey(for: .create, environment: .dev)))
        #expect(!drafts.contains(key: PostEditorViewModel.draftKey(for: .edit(id: "new-post"), environment: .dev)))
    }
    
    // MARK: - Validation
    
    /// Regression test: posts the server would reject (a title of only spaces, a reserved or too-long slug, a tag over 40 characters) could be published, and failed with "Server error (400)".
    @Test func postsTheServerWouldRejectCannotBePublished() async {
        let vm = makeViewModel(mode: .create)
        await vm.load()
        vm.title = "   "
        vm.id = "index"
        
        #expect(!vm.canSave)
        #expect(vm.validationIssues.count == 2)
        
        vm.title = "Title"
        vm.id = String(repeating: "a", count: 101)
        
        #expect(!vm.canSave)
        
        vm.id = "fine"
        vm.tags = [String(repeating: "t", count: 41)]
        
        #expect(!vm.canSave)
        
        vm.tags = ["swift"]
        
        #expect(vm.canSave)
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
    
    /// Regression test: an image uploaded and then removed before the post was published was never deleted from the server.
    @Test func uploadRemovedBeforePublishingIsDeleted() async {
        let vm = makeViewModel()
        await vm.load()
        await vm.uploadInlineImage(sampleImage)
        // The toolbar would insert it into the content; it's never inserted here, as if it was removed again.
        await vm.save()
        
        #expect(mediaRepo.deletedFiles == ["/media/posts/sample-post/upload-1.webp"])
        #expect(!vm.hasUploadedFiles)
    }
    
    /// Regression test: files that couldn't be deleted after publishing were reported as a failed publish, and never tried again.
    @Test func cleanupFailureIsReportedAndRetried() async {
        mediaRepo.deleteError = .httpError(statusCode: 500, message: "Internal server error")
        let vm = makeViewModel()
        await vm.load()
        vm.heroImage = ""
        await vm.save()
        
        #expect(vm.saved != nil)
        #expect(repo.posts[0].heroImage == nil)
        guard case .cleanupFailed(count: 1, _)? = vm.error as? APIError else {
            Issue.record("Expected a cleanup error, got \(String(describing: vm.error))")
            return
        }
        #expect(vm.hasDraft)
        
        mediaRepo.deleteError = nil
        vm.error = nil
        await vm.save()
        
        #expect(mediaRepo.deletedFiles == ["/media/posts/sample-post/hero.webp"])
        #expect(!vm.hasDraft)
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
    
    /// Regression test: a new post's ID only locked once its first upload finished, so it could be changed while the file was being stored under the old one.
    @Test func newPostsIDLocksWhileUploading() async {
        let gate = Gate()
        mediaRepo.beforeUpload = { await gate.wait() }
        let vm = makeViewModel(mode: .create)
        await vm.load()
        vm.id = "my post"
        
        let uploading = Task { await vm.uploadInlineImage(sampleImage) }
        await gate.untilArrived()
        
        #expect(vm.hasUploadedFiles)
        
        gate.open()
        await uploading.value
        
        #expect(vm.hasUploadedFiles)
    }
    
    /// Regression test: reopening a new post's draft with uploaded images unlocked its ID, though the images were stored under it.
    @Test func reopenedNewPostKeepsItsIDLocked() async {
        let vm = makeViewModel(mode: .create)
        await vm.load()
        vm.id = "my post"
        await vm.uploadInlineImage(sampleImage)
        vm.saveDraftNow()
        
        let reopened = makeViewModel(mode: .create)
        await reopened.load()
        
        #expect(reopened.id == "my post")
        #expect(reopened.hasUploadedFiles)
    }
}
