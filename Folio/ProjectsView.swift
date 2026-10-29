import SwiftUI

struct ProjectsView: View {
    @AppStorage(FolioStorageKey.activeEnvironment) private var environment = FolioEnvironment.dev
    @State private var vm: ProjectsViewModel
    private let repo: any ProjectRepositoryProtocol
    private let mediaRepo: any MediaRepositoryProtocol
    private let drafts: DraftStore
    
    init(
        repo: any ProjectRepositoryProtocol = ProjectRepository(),
        mediaRepo: any MediaRepositoryProtocol = MediaRepository(),
        drafts: DraftStore = .live
    ) {
        self._vm = State(initialValue: ProjectsViewModel(repo: repo, drafts: drafts))
        self.repo = repo
        self.mediaRepo = mediaRepo
        self.drafts = drafts
    }
    
    var body: some View {
        NavigationStack {
            List(selection: $vm.selectedID) {
                ForEach(vm.items) { project in
                    ProjectListRow(project: project)
                        .tag(project.id)
                        .contextMenu {
                            Button("Delete…", systemImage: "trash", role: .destructive) {
                                vm.requestDeletion(of: project)
                            }
                        }
                }
                .onDelete { indexSet in
                    // NOTE: - Each deletion is confirmed, so only the first of several swiped rows is offered.
                    if let index = indexSet.first { vm.requestDeletion(of: vm.items[index]) }
                }
            }
            .overlay {
                ContentListOverlay(vm: vm, noun: "Projects", systemImage: "folder", emptyDescription: "Projects you add here appear on your site.", newItemTitle: "New Project")
            }
            .navigationTitle("Projects")
            .navigationSubtitle(environment.longTitle)
            .refreshable { await vm.refresh() }
            .navigationDestination(item: $vm.selectedID) { id in
                ProjectFormView(
                    vm: ProjectFormViewModel(mode: .edit(id: id), repo: repo, mediaRepo: mediaRepo, drafts: drafts),
                    onSave: { preview in vm.appendOrReplace(preview) },
                    onDelete: { vm.remove(id: id) }
                )
            }
            .navigationDestination(isPresented: $vm.isCreatingNew) {
                ProjectFormView(
                    vm: ProjectFormViewModel(mode: .create, repo: repo, mediaRepo: mediaRepo, drafts: drafts),
                    onSave: { preview in
                        vm.appendOrReplace(preview)
                        vm.isCreatingNew = false
                    },
                    onDelete: {}
                )
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Project", systemImage: "plus") {
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
        ) { project in
            Button("Delete Project", role: .destructive) {
                Task { await vm.delete(id: project.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This deletes it from \((vm.loadedEnvironment ?? environment).longTitle), along with its unpublished draft. It can't be undone.")
        }
        .errorAlert($vm.error)
    }
}

#Preview {
    ProjectsView(repo: TestProjectRepository(), mediaRepo: TestMediaRepository(), drafts: .temporary())
}
