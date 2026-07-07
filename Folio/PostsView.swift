import SwiftUI

struct PostsView: View {
    @State private var vm = PostsViewModel()
    @State private var isCreatingNew = false
    @State private var didLoad = false
    @State private var selectedPostID: String?

    var body: some View {
        NavigationStack {
            List(selection: $selectedPostID) {
                if vm.isLoading && vm.posts.isEmpty {
                    ProgressView()
                } else {
                    ForEach(vm.posts, id: \.id) { post in
                        PostListRow(post: post)
                            .tag(post.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    Task { await vm.deletePost(id: post.id) }
                                }
                            }
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            let id = vm.posts[i].id
                            Task { await vm.deletePost(id: id) }
                        }
                    }
                }
            }
            .navigationTitle("Posts")
            .refreshable { await vm.fetchPosts() }
            .navigationDestination(item: $selectedPostID) { id in
                PostEditorView(
                    vm: PostEditorViewModel(mode: .edit(id: id)),
                    onSave: { preview in vm.appendOrReplace(preview) },
                    onDelete: { vm.posts.removeAll { $0.id == id } }
                )
            }
            .navigationDestination(isPresented: $isCreatingNew) {
                PostEditorView(
                    vm: PostEditorViewModel(mode: .create),
                    onSave: { preview in
                        vm.appendOrReplace(preview)
                        isCreatingNew = false
                    },
                    onDelete: {}
                )
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Post", systemImage: "plus") {
                        isCreatingNew = true
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await vm.fetchPosts() }
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(vm.isLoading)
                }
            }
        }
        .onDisappear { selectedPostID = nil }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await vm.fetchPosts()
        }
        .alert("Error", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("OK", role: .cancel) { vm.error = nil }
        } message: {
            Text(vm.error?.localizedDescription ?? "")
        }
    }
}

#Preview {
    PostsView()
}
