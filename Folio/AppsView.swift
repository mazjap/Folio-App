import SwiftUI

@Observable
class AppsViewModel {
    var apps: [AppRecord] = []
    
    private let storageKey = "folio.apps"
    
    func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let stored = try? JSONDecoder().decode([AppRecord].self, from: data)
        else { return }
        apps = stored
    }
    
    func addApp(id: String) {
        let slug = id.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: " ", with: "-")
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
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}

struct AppsView: View {
    @State private var vm = AppsViewModel()
    @State private var selectedAppID: String?
    @State private var showAddAlert = false
    @State private var newAppID = ""
    
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
                AppDetailView(appId: id)
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
