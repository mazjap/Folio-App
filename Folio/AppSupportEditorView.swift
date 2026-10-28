import SwiftUI

@Observable
class AppSupportEditorViewModel {
    let appId: String
    var appName: String
    var version: String
    var subtitle: String
    var content: String
    var contactUrl: String
    var contactText: String
    var pendingAction: EditorAction?
    
    var isSaving = false
    var error: APIError?
    var saved: AppSupport?
    var deleted = false
    
    let isEditing: Bool
    @ObservationIgnored private let repo: any AppsRepositoryProtocol
    
    init(appId: String, existing: AppSupport?, repo: any AppsRepositoryProtocol = AppsRepository()) {
        self.appId = appId
        self.repo = repo
        self.isEditing = existing != nil
        self.appName = existing?.appName ?? ""
        self.version = existing?.version ?? ""
        self.subtitle = existing?.subtitle ?? ""
        self.content = existing?.content ?? ""
        self.contactUrl = existing?.contactUrl ?? ""
        self.contactText = existing?.contactText ?? ""
    }
    
    func save() async {
        isSaving = true
        defer { isSaving = false }
        let support = AppSupport(
            id: appId,
            appName: appName,
            version: version,
            subtitle: subtitle,
            content: content,
            contactUrl: contactUrl.isEmpty ? nil : contactUrl,
            contactText: contactText.isEmpty ? nil : contactText
        )
        do {
            saved = try await isEditing ? repo.updateSupport(support) : repo.createSupport(support)
        } catch {
            self.error = error
        }
    }
    
    func delete() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await repo.deleteSupport(appId: appId)
            deleted = true
        } catch {
            self.error = error
        }
    }
}

struct AppSupportEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AppSupportEditorViewModel
    private let onSave: (AppSupport) -> Void
    private let onDelete: () -> Void
    
    @State private var showDeleteConfirm = false
    
    init(appId: String, repo: any AppsRepositoryProtocol = AppsRepository(), existing: AppSupport?, onSave: @escaping (AppSupport) -> Void, onDelete: @escaping () -> Void) {
        self._vm = State(initialValue: AppSupportEditorViewModel(appId: appId, existing: existing, repo: repo))
        self.onSave = onSave
        self.onDelete = onDelete
    }
    
    var body: some View {
        Form {
            Section("App Info") {
                TextField("App Name", text: $vm.appName)
                TextField("Version", text: $vm.version, prompt: Text("2.1.0"))
                TextField("Subtitle", text: $vm.subtitle, axis: .vertical)
                    .lineLimit(2...4)
            }
            
            Section("Content") {
                MarkdownToolbar(pendingAction: $vm.pendingAction)
                MarkdownEditorView(text: $vm.content, pendingAction: $vm.pendingAction)
                    .frame(minHeight: 200)
            }
            
            Section("Contact (optional)") {
                TextField("Contact URL", text: $vm.contactUrl, prompt: Text("https://…"))
                    .textContentType(.URL)
                    #if !os(macOS)
                    .keyboardType(.URL)
                    #endif
                TextField("Contact label", text: $vm.contactText, prompt: Text("Visit Website"))
            }
            
            if vm.isEditing {
                Section {
                    Button("Delete Support Page", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(vm.isEditing ? "Support" : "New Support Page")
        .toolbar { toolbarContent }
        .onChange(of: vm.saved) { _, support in
            if let support {
                onSave(support)
                dismiss()
            }
        }
        .onChange(of: vm.deleted) { _, isDeleted in
            if isDeleted {
                onDelete()
                dismiss()
            }
        }
        .errorAlert($vm.error)
        .confirmationDialog("Delete support page?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await vm.delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button(vm.isEditing ? "Save" : "Create", systemImage: "square.and.arrow.up") {
                Task { await vm.save() }
            }
            .disabled(vm.appName.isEmpty || vm.version.isEmpty || vm.isSaving)
            .keyboardShortcut("s", modifiers: .command)
        }
        if vm.isSaving {
            ToolbarItem(placement: .status) { ProgressView() }
        }
    }
}

#Preview {
    NavigationStack {
        AppSupportEditorView(appId: AppSupport.sample.id, repo: TestAppsRepository(), existing: .sample, onSave: { _ in }, onDelete: {})
    }
}
