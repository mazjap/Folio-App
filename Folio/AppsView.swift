import SwiftUI

struct AppsView: View {
    @AppStorage(FolioStorageKey.activeEnvironment) private var environment = FolioEnvironment.dev
    @State private var vm: AppsViewModel
    @State private var newAppID = ""
    private let repo: any AppsRepositoryProtocol
    
    init(repo: any AppsRepositoryProtocol = AppsRepository(), userDefaults: UserDefaults = .standard) {
        self._vm = State(initialValue: AppsViewModel(repo: repo, userDefaults: userDefaults))
        self.repo = repo
    }
    
    var body: some View {
        NavigationStack {
            List(selection: $vm.selectedID) {
                ForEach(vm.items) { app in
                    AppListRow(app: app)
                        .tag(app.id)
                }
            }
            .overlay {
                ContentListOverlay(vm: vm, noun: "Apps", systemImage: "square.grid.2x2", emptyDescription: "Add an app's URL slug to write its privacy policy and support pages.", newItemTitle: "Add App")
            }
            .navigationTitle("Apps")
            .navigationSubtitle(environment.longTitle)
            .refreshable { await vm.refresh() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add App", systemImage: "plus") {
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
            .navigationDestination(item: $vm.selectedID) { id in
                AppDetailView(appId: id, repo: repo)
            }
            // NOTE: - "Creating" an app is naming it: it's only on the server once one of its pages is saved.
            .alert("Add App", isPresented: $vm.isCreatingNew) {
                TextField("ID slug (e.g. trekpoint)", text: $newAppID)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Button("Add") {
                    vm.selectedID = vm.addApp(id: newAppID)
                    newAppID = ""
                }
                Button("Cancel", role: .cancel) { newAppID = "" }
            } message: {
                Text("Enter the app's URL slug on the portfolio site. It's listed on every device once it has a page.")
            }
        }
        .onDisappear { vm.clearSelection() }
        .task { await vm.loadIfNeeded() }
        .onChange(of: environment) {
            Task { await vm.environmentDidChange() }
        }
        // NOTE: - Pages created or deleted in the detail view change what the list shows.
        .onChange(of: vm.selectedID) { oldID, newID in
            if oldID != nil, newID == nil { Task { await vm.refresh() } }
        }
        .errorAlert($vm.error)
    }
}

// MARK: - Row

/// An app in the list: its name, ID, and which pages it has.
private struct AppListRow: View {
    private let app: AppSummary
    
    init(app: AppSummary) {
        self.app = app
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(app.appName)
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var details: String {
        let pages = app.pages.map { page in
            switch page {
            case .privacyPolicy: "Privacy Policy"
            case .support: "Support"
            }
        }
        return ([app.id] + (pages.isEmpty ? ["No pages yet"] : pages)).joined(separator: " · ")
    }
}

#Preview {
    AppsView(repo: TestAppsRepository())
}
