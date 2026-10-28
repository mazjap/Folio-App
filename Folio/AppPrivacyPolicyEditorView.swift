import SwiftUI

@Observable
class AppPrivacyPolicyEditorViewModel {
    let appId: String
    var appName: String
    var lastUpdated: Date
    var content: String
    var contactUrl: String
    var contactText: String
    var pendingAction: EditorAction?
    
    var isSaving = false
    var error: APIError?
    var saved: AppPrivacyPolicy?
    var deleted = false
    
    let isEditing: Bool
    @ObservationIgnored private let repo: any AppsRepositoryProtocol
    
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()
    
    init(appId: String, existing: AppPrivacyPolicy?, repo: any AppsRepositoryProtocol = AppsRepository()) {
        self.appId = appId
        self.repo = repo
        self.isEditing = existing != nil
        self.appName = existing?.appName ?? ""
        self.lastUpdated = existing.flatMap { Self.dateFormatter.date(from: $0.lastUpdated) } ?? Date()
        self.content = existing?.content ?? ""
        self.contactUrl = existing?.contactUrl ?? ""
        self.contactText = existing?.contactText ?? ""
    }
    
    func save() async {
        isSaving = true
        defer { isSaving = false }
        let policy = AppPrivacyPolicy(
            id: appId,
            appName: appName,
            lastUpdated: Self.dateFormatter.string(from: lastUpdated),
            content: content,
            contactUrl: contactUrl.isEmpty ? nil : contactUrl,
            contactText: contactText.isEmpty ? nil : contactText
        )
        do {
            saved = try await isEditing ? repo.updatePrivacyPolicy(policy) : repo.createPrivacyPolicy(policy)
        } catch {
            self.error = error
        }
    }
    
    func delete() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await repo.deletePrivacyPolicy(appId: appId)
            deleted = true
        } catch {
            self.error = error
        }
    }
}

struct AppPrivacyPolicyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: AppPrivacyPolicyEditorViewModel
    private let onSave: (AppPrivacyPolicy) -> Void
    private let onDelete: () -> Void
    
    @State private var showDeleteConfirm = false
    
    init(appId: String, repo: any AppsRepositoryProtocol = AppsRepository(), existing: AppPrivacyPolicy?, onSave: @escaping (AppPrivacyPolicy) -> Void, onDelete: @escaping () -> Void) {
        self._vm = State(initialValue: AppPrivacyPolicyEditorViewModel(appId: appId, existing: existing, repo: repo))
        self.onSave = onSave
        self.onDelete = onDelete
    }
    
    var body: some View {
        Form {
            Section("App Info") {
                TextField("App Name", text: $vm.appName)
                DatePicker("Last Updated", selection: $vm.lastUpdated, displayedComponents: .date)
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
                TextField("Contact label", text: $vm.contactText, prompt: Text("Contact Support"))
            }
            
            if vm.isEditing {
                Section {
                    Button("Delete Privacy Policy", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(vm.isEditing ? "Privacy Policy" : "New Privacy Policy")
        .toolbar { toolbarContent }
        .onChange(of: vm.saved) { _, policy in
            if let policy {
                onSave(policy)
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
        .confirmationDialog("Delete privacy policy?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
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
            .disabled(vm.appName.isEmpty || vm.isSaving)
            .keyboardShortcut("s", modifiers: .command)
        }
        if vm.isSaving {
            ToolbarItem(placement: .status) { ProgressView() }
        }
    }
}

#Preview {
    NavigationStack {
        AppPrivacyPolicyEditorView(appId: AppPrivacyPolicy.sample.id, repo: TestAppsRepository(), existing: .sample, onSave: { _ in }, onDelete: {})
    }
}
