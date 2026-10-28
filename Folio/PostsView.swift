import SwiftUI

struct PostsView: View {
    @State private var vm: PostsViewModel
    private let repo: any PostRepositoryProtocol
    private let mediaRepo: any MediaRepositoryProtocol
    private let drafts: DraftStore
    
    init(
        repo: any PostRepositoryProtocol = PostRepository(),
        mediaRepo: any MediaRepositoryProtocol = MediaRepository(),
        drafts: DraftStore = .live
    ) {
        self._vm = State(initialValue: PostsViewModel(repo: repo, drafts: drafts))
        self.repo = repo
        self.mediaRepo = mediaRepo
        self.drafts = drafts
    }
    
    var body: some View {
        NavigationStack {
            List(selection: $vm.selectedID) {
                if vm.isLoading && vm.items.isEmpty {
                    ProgressView()
                } else {
                    ForEach(vm.items) { post in
                        PostListRow(post: post)
                            .tag(post.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    Task { await vm.delete(id: post.id) }
                                }
                            }
                    }
                    .onDelete { indexSet in
                        for id in indexSet.map({ vm.items[$0].id }) {
                            Task { await vm.delete(id: id) }
                        }
                    }
                }
            }
            .navigationTitle("Posts")
            .refreshable { await vm.refresh() }
            .navigationDestination(item: $vm.selectedID) { id in
                PostEditorView(
                    vm: PostEditorViewModel(mode: .edit(id: id), repo: repo, mediaRepo: mediaRepo, drafts: drafts),
                    onSave: { preview in vm.appendOrReplace(preview) },
                    onDelete: { vm.remove(id: id) }
                )
            }
            .navigationDestination(isPresented: $vm.isCreatingNew) {
                PostEditorView(
                    vm: PostEditorViewModel(mode: .create, repo: repo, mediaRepo: mediaRepo, drafts: drafts),
                    onSave: { preview in
                        vm.appendOrReplace(preview)
                        vm.isCreatingNew = false
                    },
                    onDelete: {}
                )
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Post", systemImage: "plus") {
                        vm.startCreating()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await vm.refresh() }
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(vm.isLoading)
                }
            }
        }
        .onDisappear { vm.clearSelection() }
        .task { await vm.loadIfNeeded() }
        .errorAlert($vm.error)
    }
}

#Preview {
    PostsView(repo: TestPostRepository(), mediaRepo: TestMediaRepository(), drafts: .temporary())
}
