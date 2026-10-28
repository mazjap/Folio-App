import SwiftUI

@Observable
class AppsViewModel {
    var apps: [AppRecord] = []
    
    @ObservationIgnored private let userDefaults: UserDefaults
    
    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    // MARK: - Functions
    
    func load() {
        guard let data = userDefaults.data(forKey: FolioStorageKey.apps),
              let stored = try? JSONDecoder().decode([AppRecord].self, from: data)
        else { return }
        
        apps = stored
    }
    
    func addApp(id: String) {
        let slug = id.slugified
        guard !slug.isEmpty, !apps.contains(where: { $0.id == slug }) else { return }
        
        apps.append(AppRecord(id: slug))
        persist()
    }
    
    func delete(app: AppRecord) {
        apps.removeAll { $0.id == app.id }
        persist()
    }
    
    private func persist() {
        guard let data = try? JSONEncoder().encode(apps) else { return }
        
        userDefaults.set(data, forKey: FolioStorageKey.apps)
    }
}

struct AppsView: View {
    @State private var vm: AppsViewModel
    @State private var selectedAppID: String?
    @State private var showAddAlert = false
    @State private var newAppID = ""
    private let repo: any AppsRepositoryProtocol
    
    init(vm: AppsViewModel = AppsViewModel(), repo: any AppsRepositoryProtocol = AppsRepository()) {
        self._vm = State(initialValue: vm)
        self.repo = repo
    }
    
    var body: some View {
        NavigationStack {
            List(selection: $selectedAppID) {
                ForEach(vm.apps) { app in
                    Text(app.id)
                        .tag(app.id)
                        .contextMenu {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                if selectedAppID == app.id { selectedAppID = nil }
                                vm.delete(app: app)
                            }
                        }
                }
            }
            .navigationTitle("Apps")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add App", systemImage: "plus") { showAddAlert = true }
                }
            }
            .navigationDestination(item: $selectedAppID) { id in
                AppDetailView(appId: id, repo: repo)
            }
            .alert("Add App", isPresented: $showAddAlert) {
                TextField("ID slug (e.g. trekpoint)", text: $newAppID)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                Button("Add") {
                    vm.addApp(id: newAppID)
                    newAppID = ""
                }
                Button("Cancel", role: .cancel) { newAppID = "" }
            } message: {
                Text("Enter the app's URL slug used on the portfolio site.")
            }
        }
        .onAppear { vm.load() }
        .onDisappear { selectedAppID = nil }
    }
}

#Preview {
    let vm = AppsViewModel(userDefaults: UserDefaults(suiteName: "FolioPreview") ?? .standard)
    vm.apps = [AppRecord(id: AppPrivacyPolicy.sample.id)]
    
    return AppsView(vm: vm, repo: TestAppsRepository())
}
