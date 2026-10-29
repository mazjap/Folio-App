import Foundation
import Testing
@testable import Folio

@MainActor
@Suite
struct ContentListViewModelTests {
    let repo = TestPostRepository()
    let drafts = DraftStore.temporary()
    let defaults = makeUserDefaults(environment: .dev)
    
    func makeViewModel() -> PostsViewModel {
        PostsViewModel(repo: repo, drafts: drafts, userDefaults: defaults)
    }
    
    /// Regression test: tapping New Post with a post selected didn't clear the selection, so the selected post's editor opened instead of a new one.
    @Test func startingANewItemClearsTheSelection() {
        let vm = makeViewModel()
        vm.selectedID = PostDetail.sample.id
        vm.startCreating()
        
        #expect(vm.selectedID == nil)
        #expect(vm.isCreatingNew)
    }
    
    @Test func loadsOnlyOnce() async {
        let vm = makeViewModel()
        await vm.loadIfNeeded()
        repo.posts = []
        await vm.loadIfNeeded()
        
        #expect(vm.items == [PostDetail.sample.preview])
    }
    
    @Test func deletingAPostDeletesItsDraft() async throws {
        let key = PostEditorViewModel.draftKey(for: .edit(id: PostDetail.sample.id), environment: .dev)
        try drafts.save(["unsaved": "work"], key: key)
        let vm = makeViewModel()
        await vm.refresh()
        vm.selectedID = PostDetail.sample.id
        await vm.delete(id: PostDetail.sample.id)
        
        #expect(vm.items.isEmpty)
        #expect(vm.selectedID == nil)
        #expect(repo.deletedIDs == [PostDetail.sample.id])
        #expect(!drafts.contains(key: key))
    }
    
    /// Regression test: deleting from the list's context menu or by swiping deleted straight away, with no confirmation.
    @Test func listDeletionWaitsForConfirmation() async {
        let vm = makeViewModel()
        await vm.refresh()
        vm.requestDeletion(of: vm.items[0])
        
        #expect(vm.pendingDeletion == PostDetail.sample.preview)
        #expect(repo.deletedIDs.isEmpty)
    }
    
    /// Regression test: a cancelled first load (like switching tabs before it finished) left the list's spinner showing, and it never loaded again.
    @Test func cancelledFirstLoadIsTriedAgain() async {
        repo.listError = .networkFailed(URLError(.cancelled))
        let vm = makeViewModel()
        await vm.loadIfNeeded()
        
        #expect(vm.items.isEmpty)
        #expect(vm.loadError == nil)
        
        repo.listError = nil
        await vm.loadIfNeeded()
        
        #expect(vm.items == [PostDetail.sample.preview])
        #expect(vm.hasFinishedLoading)
    }
    
    /// Regression test: a slow refresh that finished after a post was saved replaced the list with its older items.
    @Test func olderLoadDoesNotReplaceNewerItems() async {
        let gate = Gate()
        repo.beforeList = { await gate.wait() }
        let vm = makeViewModel()
        
        let loading = Task { await vm.refresh() }
        await gate.untilArrived()
        var saved = PostDetail.sample.preview
        saved.title = "Saved while loading"
        vm.appendOrReplace(saved)
        gate.open()
        await loading.value
        
        #expect(vm.items == [saved])
        #expect(!vm.isLoading)
    }
    
    /// Regression test: after switching environments, the list kept showing the other server's posts, and deleting one sent its ID to the new server.
    @Test func switchingEnvironmentsReloadsTheList() async {
        let vm = makeViewModel()
        await vm.refresh()
        vm.selectedID = PostDetail.sample.id
        
        defaults.set(FolioEnvironment.prod.rawValue, forKey: FolioStorageKey.activeEnvironment)
        await vm.delete(id: PostDetail.sample.id)
        
        #expect(repo.deletedIDs.isEmpty)
        #expect(vm.error != nil)
        
        repo.posts = []
        await vm.environmentDidChange()
        
        #expect(vm.items.isEmpty)
        #expect(vm.selectedID == nil)
        #expect(vm.loadedEnvironment == .prod)
    }
    
    @Test func savedItemsReplaceOrInsert() {
        let vm = makeViewModel()
        var post = PostDetail.sample.preview
        vm.appendOrReplace(post)
        post.title = "Renamed"
        vm.appendOrReplace(post)
        
        #expect(vm.items == [post])
    }
}
