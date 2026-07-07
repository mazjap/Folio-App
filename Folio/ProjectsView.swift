import SwiftUI

struct ProjectsView: View {
    @State private var vm = ProjectsViewModel()
    @State private var isCreatingNew = false
    @State private var didLoad = false
    @State private var selectedProjectID: String?

    var body: some View {
        NavigationStack {
            List(selection: $selectedProjectID) {
                if vm.isLoading && vm.projects.isEmpty {
                    ProgressView()
                } else {
                    ForEach(vm.projects, id: \.id) { project in
                        ProjectListRow(project: project)
                            .tag(project.id)
                            .contextMenu {
                                Button("Delete", role: .destructive) {
                                    Task { await vm.deleteProject(id: project.id) }
                                }
                            }
                    }
                    .onDelete { indexSet in
                        for i in indexSet {
                            let id = vm.projects[i].id
                            Task { await vm.deleteProject(id: id) }
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .refreshable { await vm.fetchProjects() }
            .navigationDestination(item: $selectedProjectID) { id in
                ProjectFormView(
                    vm: ProjectFormViewModel(mode: .edit(id: id)),
                    onSave: { preview in vm.appendOrReplace(preview) },
                    onDelete: { vm.projects.removeAll { $0.id == id } }
                )
            }
            .navigationDestination(isPresented: $isCreatingNew) {
                ProjectFormView(
                    vm: ProjectFormViewModel(mode: .create),
                    onSave: { preview in
                        vm.appendOrReplace(preview)
                        isCreatingNew = false
                    },
                    onDelete: {}
                )
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("New Project", systemImage: "plus") {
                        isCreatingNew = true
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        Task { await vm.fetchProjects() }
                    }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(vm.isLoading)
                }
            }
        }
        .onDisappear { selectedProjectID = nil }
        .task {
            guard !didLoad else { return }
            didLoad = true
            await vm.fetchProjects()
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
    ProjectsView()
}
