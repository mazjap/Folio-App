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
    private let repo = AppsRepository()

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        return df
    }()

    init(appId: String, existing: AppPrivacyPolicy?) {
        self.appId = appId
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
    let onSave: (AppPrivacyPolicy) -> Void
    let onDelete: () -> Void

    @State private var showDeleteConfirm = false

    init(appId: String, existing: AppPrivacyPolicy?, onSave: @escaping (AppPrivacyPolicy) -> Void, onDelete: @escaping () -> Void) {
        self._vm = State(initialValue: AppPrivacyPolicyEditorViewModel(appId: appId, existing: existing))
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
                markdownToolbar
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
            if let policy { onSave(policy); dismiss() }
        }
        .onChange(of: vm.deleted) { _, gone in
            if gone { onDelete(); dismiss() }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("OK", role: .cancel) { vm.error = nil }
        } message: {
            Text(vm.error?.localizedDescription ?? "")
        }
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

    private var markdownToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                mdButton("B", title: "Bold") { vm.pendingAction = .wrap(prefix: "**", suffix: "**", placeholder: "text") }
                mdButton("I", title: "Italic") { vm.pendingAction = .wrap(prefix: "_", suffix: "_", placeholder: "text") }
                mdButton("` `", title: "Code") { vm.pendingAction = .wrap(prefix: "`", suffix: "`", placeholder: "code") }
                Divider().frame(height: 20)
                mdButton("H1", title: "Heading 1") { vm.pendingAction = .prependLine("# ") }
                mdButton("H2", title: "Heading 2") { vm.pendingAction = .prependLine("## ") }
                mdButton("H3", title: "Heading 3") { vm.pendingAction = .prependLine("### ") }
                Divider().frame(height: 20)
                mdButton("[ ]", title: "Link") { vm.pendingAction = .wrap(prefix: "[", suffix: "](url)", placeholder: "text") }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(.bar)
    }

    private func mdButton(_ label: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
