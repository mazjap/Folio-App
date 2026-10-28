import SwiftUI

struct ProjectsView: View {
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
                if vm.isLoading && vm.items.isEmpty {
                    ProgressView()
                } else {
                    ForEach(vm.items) { project in
                        ProjectListRow(project: project)
                            .tag(project.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    Task { await vm.delete(id: project.id) }
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
            .navigationTitle("Projects")
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
        .errorAlert($vm.error)
    }
}

#Preview {
    ProjectsView(repo: TestProjectRepository(), mediaRepo: TestMediaRepository(), drafts: .temporary())
}
