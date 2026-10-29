import SwiftUI

struct AppSupportEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: AppSupportEditorViewModel
    private let onSave: (AppSupport) -> Void
    private let onDelete: () -> Void
    
    @State private var showDeleteConfirm = false
    @State private var showDiscardDraftConfirm = false
    @State private var showPreview = false
    
    init(appId: String, repo: any AppsRepositoryProtocol = AppsRepository(), drafts: DraftStore = .live, existing: AppSupport?, onSave: @escaping (AppSupport) -> Void, onDelete: @escaping () -> Void) {
        self._vm = State(initialValue: AppSupportEditorViewModel(appId: appId, existing: existing, repo: repo, drafts: drafts))
        self.onSave = onSave
        self.onDelete = onDelete
    }
    
    var body: some View {
        Form {
            if !vm.validationIssues.isEmpty {
                Section {
                    ValidationIssuesView(issues: vm.validationIssues)
                }
            }
            
            Section("App Info") {
                LabeledTextField("App Name", text: $vm.appName)
                LabeledTextField("Version", text: $vm.version, prompt: "2.1.0")
                LabeledTextField("Subtitle", text: $vm.subtitle, axis: .vertical)
                    .lineLimit(1...4)
            }
            
            Section("Content") {
                if showPreview {
                    MarkdownPreview(markdown: vm.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownToolbar(pendingAction: $vm.pendingAction)
                    MarkdownEditorView(text: $vm.content, pendingAction: $vm.pendingAction)
                        .frame(minHeight: 200)
                }
            }
            
            Section {
                LabeledTextField("Contact URL", text: $vm.contactUrl, prompt: "https://… or mailto:…")
                    .textContentType(.URL)
                    #if !os(macOS)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
                LabeledTextField("Contact Button Title", text: $vm.contactText, prompt: "Visit Website")
            } header: {
                Text("Contact")
            } footer: {
                Text("Optional. Shown as a button at the end of the page.")
            }
            
            if vm.isEditing {
                Section {
                    Button("Delete Support Page…", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(vm.isSaving)
                }
            }
        }
        .formStyle(.grouped)
        // NOTE: - Saving closes the editor, so it's not edited while a save is in flight.
        .disabled(vm.isSaving)
        .navigationTitle(vm.isEditing ? "Support" : "New Support Page")
        .navigationSubtitle(vm.environment.longTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { vm.load() }
        .onDisappear { vm.saveDraftNow() }
        .onChange(of: scenePhase) {
            if scenePhase != .active { vm.saveDraftNow() }
        }
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
            Button("Delete Support Page", role: .destructive) { Task { await vm.delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes it from \(vm.environment.longTitle), and links to it from the App Store stop working. It can't be undone.")
        }
        .confirmationDialog("Discard draft?", isPresented: $showDiscardDraftConfirm, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { vm.discardDraft() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Reverts to the saved version.")
        }
    }
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if vm.draftSession.isFailing {
            ToolbarItem(placement: .primaryAction) {
                DraftNotSavedLabel()
            }
        }
        if vm.hasDraft {
            ToolbarItem(placement: .primaryAction) {
                DraftMenu {
                    showDiscardDraftConfirm = true
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle("Preview", systemImage: "eye", isOn: $showPreview)
                .help("Preview the rendered page")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            SaveToolbarButton(vm.isEditing ? "Save" : "Create", isSaving: vm.isSaving, isDisabled: !vm.canSave) {
                Task { await vm.save() }
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppSupportEditorView(appId: AppSupport.sample.id, repo: TestAppsRepository(), drafts: .temporary(), existing: .sample, onSave: { _ in }, onDelete: {})
    }
}
