import Foundation
import Testing
@testable import Folio

@MainActor
@Suite
struct ContentListViewModelTests {
    let repo = TestPostRepository()
    let drafts = DraftStore.temporary()
    
    /// Regression test: tapping New Post with a post selected didn't clear the selection, so the selected post's editor opened instead of a new one.
    @Test func startingANewItemClearsTheSelection() {
        let vm = PostsViewModel(repo: repo, drafts: drafts)
        vm.selectedID = PostDetail.sample.id
        vm.startCreating()
        
        #expect(vm.selectedID == nil)
        #expect(vm.isCreatingNew)
    }
    
    @Test func loadsOnlyOnce() async {
        let vm = PostsViewModel(repo: repo, drafts: drafts)
        await vm.loadIfNeeded()
        repo.posts = []
        await vm.loadIfNeeded()
        
        #expect(vm.items == [PostDetail.sample.preview])
    }
    
    @Test func deletingAPostDeletesItsDraft() async {
        let key = PostEditorViewModel.draftKey(for: .edit(id: PostDetail.sample.id))
        drafts.save(["unsaved": "work"], key: key)
        let vm = PostsViewModel(repo: repo, drafts: drafts)
        await vm.refresh()
        vm.selectedID = PostDetail.sample.id
        await vm.delete(id: PostDetail.sample.id)
        
        #expect(vm.items.isEmpty)
        #expect(vm.selectedID == nil)
        #expect(repo.deletedIDs == [PostDetail.sample.id])
        #expect(!drafts.contains(key: key))
    }
    
    @Test func savedItemsReplaceOrInsert() {
        let vm = PostsViewModel(repo: repo, drafts: drafts)
        var post = PostDetail.sample.preview
        vm.appendOrReplace(post)
        post.title = "Renamed"
        vm.appendOrReplace(post)
        
        #expect(vm.items == [post])
    }
}
