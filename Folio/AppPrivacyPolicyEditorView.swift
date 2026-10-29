import SwiftUI

struct AppPrivacyPolicyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: AppPrivacyPolicyEditorViewModel
    private let onSave: (AppPrivacyPolicy) -> Void
    private let onDelete: () -> Void
    
    @State private var showDeleteConfirm = false
    @State private var showDiscardDraftConfirm = false
    @State private var showPreview = false
    
    init(appId: String, repo: any AppsRepositoryProtocol = AppsRepository(), drafts: DraftStore = .live, existing: AppPrivacyPolicy?, onSave: @escaping (AppPrivacyPolicy) -> Void, onDelete: @escaping () -> Void) {
        self._vm = State(initialValue: AppPrivacyPolicyEditorViewModel(appId: appId, existing: existing, repo: repo, drafts: drafts))
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
                DatePicker(
                    "Last Updated",
                    selection: Binding(
                        get: { vm.lastUpdated },
                        set: { vm.lastUpdated = $0.calendarDay(in: .gmt) }
                    ),
                    displayedComponents: .date
                )
                // NOTE: - The date is a calendar day stored as midnight UTC, so it's shown in UTC to match what's saved.
                .environment(\.timeZone, .gmt)
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
                LabeledTextField("Contact Button Title", text: $vm.contactText, prompt: "Contact Support")
            } header: {
                Text("Contact")
            } footer: {
                Text("Optional. Shown as a button at the end of the page.")
            }
            
            if vm.isEditing {
                Section {
                    Button("Delete Privacy Policy…", role: .destructive) {
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
        .navigationTitle(vm.isEditing ? "Privacy Policy" : "New Privacy Policy")
        .navigationSubtitle(vm.environment.longTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { vm.load() }
        .onDisappear { vm.saveDraftNow() }
        .onChange(of: scenePhase) {
            if scenePhase != .active { vm.saveDraftNow() }
        }
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
            Button("Delete Privacy Policy", role: .destructive) { Task { await vm.delete() } }
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
                .help("Preview the rendered policy")
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
        AppPrivacyPolicyEditorView(appId: AppPrivacyPolicy.sample.id, repo: TestAppsRepository(), drafts: .temporary(), existing: .sample, onSave: { _ in }, onDelete: {})
    }
}
