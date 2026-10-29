import SwiftUI

struct PostsView: View {
    @AppStorage(FolioStorageKey.activeEnvironment) private var environment = FolioEnvironment.dev
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
                ForEach(vm.items) { post in
                    PostListRow(post: post)
                        .tag(post.id)
                        .contextMenu {
                            Button("Delete…", systemImage: "trash", role: .destructive) {
                                vm.requestDeletion(of: post)
                            }
                        }
                }
                .onDelete { indexSet in
                    // NOTE: - Each deletion is confirmed, so only the first of several swiped rows is offered.
                    if let index = indexSet.first { vm.requestDeletion(of: vm.items[index]) }
                }
            }
            .overlay {
                ContentListOverlay(vm: vm, noun: "Posts", systemImage: "doc.text", emptyDescription: "Posts you write here are published to your site.", newItemTitle: "New Post")
            }
            .navigationTitle("Posts")
            .navigationSubtitle(environment.longTitle)
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
        .onChange(of: environment) {
            Task { await vm.environmentDidChange() }
        }
        .confirmationDialog(
            "Delete “\(vm.pendingDeletion?.title ?? "")”?",
            isPresented: Binding(
                get: { vm.pendingDeletion != nil },
                set: { if !$0 { vm.pendingDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: vm.pendingDeletion
        ) { post in
            Button("Delete Post", role: .destructive) {
                Task { await vm.delete(id: post.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This deletes it from \((vm.loadedEnvironment ?? environment).longTitle), along with its unpublished draft. It can't be undone.")
        }
        .errorAlert($vm.error)
    }
}

#Preview {
    PostsView(repo: TestPostRepository(), mediaRepo: TestMediaRepository(), drafts: .temporary())
}
