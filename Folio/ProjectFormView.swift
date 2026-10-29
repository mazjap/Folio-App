import SwiftUI

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: ProjectFormViewModel
    private let onSave: (ProjectPreview) -> Void
    private let onDelete: () -> Void
    
    @State private var showInspector = true
    @State private var showDeleteConfirm = false
    @State private var showDiscardDraftConfirm = false
    @State private var showDiff = false
    @State private var showPreview = false
    @State private var diffDescriptionRanges: [NSRange] = []
    @State private var newTag = ""
    @State private var newLinkName = ""
    @State private var newLinkURL = ""
    
    init(vm: ProjectFormViewModel, onSave: @escaping (ProjectPreview) -> Void, onDelete: @escaping () -> Void) {
        self._vm = State(initialValue: vm)
        self.onSave = onSave
        self.onDelete = onDelete
    }
    
    var body: some View {
        Form {
            if case .failed(_, showsDraft: true) = vm.loadState {
                Section {
                    LoadProblemBanner(state: vm.loadState, itemKind: "project") {
                        Task { await vm.load() }
                    }
                }
            }
            
            if vm.loadState == .loaded, !vm.validationIssues.isEmpty {
                Section {
                    ValidationIssuesView(issues: vm.validationIssues)
                }
            }
            
            Section("Details") {
                if case .create = vm.mode {
                    LabeledTextField("URL Slug", text: $vm.id, prompt: "my-project")
                        .textContentType(.none)
                        #if !os(macOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        #endif
                        .disabled(vm.hasUploadedFiles)
                        .help(vm.hasUploadedFiles ? "Images are uploaded under this ID, so it can't change." : "")
                    if !vm.currentID.isEmpty {
                        LabeledContent("Published At", value: "/projects/\(vm.currentID)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledTextField("Title", text: $vm.title)
                LabeledTextField("Tagline", text: $vm.tagline, prompt: "One line about the project", axis: .vertical)
                LabeledTextField("Category", text: $vm.category, prompt: "iOS App, Web, macOS App…")
            }
            
            Section("Hero Image") {
                HeroImageRow(heroImage: $vm.heroImage, pendingHeroImage: $vm.pendingHeroImage, uploadsOn: "save")
            }
            
            Section("Description") {
                if showPreview {
                    MarkdownPreview(markdown: vm.description)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    MarkdownToolbar(pendingAction: $vm.pendingDescriptionAction) {
                        InsertImageButtons(isEnabled: vm.canUploadFiles) { image in
                            await vm.uploadInlineImageToDescription(image)
                        }
                    }
                    MarkdownEditorView(text: $vm.description, pendingAction: $vm.pendingDescriptionAction, highlightRanges: (showDiff && vm.hasDraft) ? diffDescriptionRanges : [])
                        .frame(minHeight: 160)
                }
            }
            
            Section("Tech Stack") {
                techStackRows
            }
            
            Section("Links") {
                linksRows
            }
            
            Section("Media") {
                MediaManagerView(media: $vm.media, isUploadEnabled: vm.canUploadFiles, isUploading: vm.isUploadingMedia) { images in
                    await vm.addMedia(images)
                }
            }
        }
        .formStyle(.grouped)
        .disabled(vm.loadState == .loading)
        .overlay {
            LoadStateOverlay(state: vm.loadState, itemKind: "project") {
                Task { await vm.load() }
            }
        }
        .navigationTitle(vm.title.isEmpty ? "New Project" : vm.title)
        .navigationSubtitle(vm.environment.longTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .inspector(isPresented: $showInspector) {
            inspectorContent
        }
        .task { await vm.load() }
        .onDisappear { vm.saveDraftNow() }
        .onChange(of: scenePhase) {
            // NOTE: - The app can be suspended or quit from the background without the editor disappearing, so save before that.
            if scenePhase != .active { vm.saveDraftNow() }
        }
        .onChange(of: showDiff) {
            diffDescriptionRanges = showDiff ? vm.computeDiffDescriptionRanges() : []
        }
        .onChange(of: vm.description) {
            guard showDiff else { return }
            
            diffDescriptionRanges = vm.computeDiffDescriptionRanges()
        }
        .onChange(of: vm.hasDraft) {
            if !vm.hasDraft {
                showDiff = false
                diffDescriptionRanges = []
            }
        }
        .onChange(of: vm.saved) { _, preview in
            if let preview { onSave(preview) }
        }
        .onChange(of: vm.deleted) { _, isDeleted in
            if isDeleted {
                onDelete()
                dismiss()
            }
        }
        .errorAlert($vm.error)
        .staleDraftAlert(isPresented: $vm.isDraftStale, itemKind: "project", isLegacy: vm.isDraftLegacy, onKeep: vm.keepStaleDraft, onDiscard: vm.discardDraft)
        .confirmationDialog("Delete “\(vm.title)”?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Project", role: .destructive) { Task { await vm.delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes it from \(vm.environment.longTitle), along with its unpublished draft. It can't be undone.")
        }
        .confirmationDialog("Discard draft?", isPresented: $showDiscardDraftConfirm, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { vm.discardDraft() }
            Button("Keep editing", role: .cancel) {}
        } message: {
            Text("Reverts to the last published version.")
        }
    }
    
    // MARK: - Tech stack
    
    @ViewBuilder
    private var techStackRows: some View {
        ForEach(vm.techStack, id: \.self) { tag in
            HStack {
                Text(tag)
                Spacer()
                Button("Remove \(tag)", systemImage: "xmark.circle.fill", role: .destructive) {
                    vm.techStack.removeAll { $0 == tag }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
            }
        }
        HStack {
            TextField("Add technology…", text: $newTag)
                .onSubmit { addTag() }
            Button("Add", action: addTag)
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
    
    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !vm.techStack.contains(trimmed) else { return }
        
        vm.techStack.append(trimmed)
        newTag = ""
    }
    
    // MARK: - Links
    
    @ViewBuilder
    private var linksRows: some View {
        ForEach(vm.links.keys.sorted(), id: \.self) { key in
            HStack {
                Text(key)
                Spacer()
                Text(vm.links[key] ?? "")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Button("Remove \(key) Link", systemImage: "xmark.circle.fill", role: .destructive) {
                    vm.links.removeValue(forKey: key)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
            }
        }
        VStack(alignment: .leading, spacing: 8) {
            TextField("Link name", text: $newLinkName, prompt: Text("Name, like GitHub"))
            TextField("URL", text: $newLinkURL, prompt: Text("https://…"))
                .textContentType(.URL)
                #if !os(macOS)
                .keyboardType(.URL)
                #endif
                .onSubmit { addLink() }
            if !newLinkURL.isEmpty, let issue = newLinkIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Add Link", systemImage: "plus", action: addLink)
                .disabled(newLinkIssue != nil)
        }
    }
    
    private var newLinkIssue: String? {
        ProjectFormViewModel.linkIssue(name: newLinkName.trimmingCharacters(in: .whitespaces), url: newLinkURL.trimmingCharacters(in: .whitespaces))
    }
    
    private func addLink() {
        let name = newLinkName.trimmingCharacters(in: .whitespaces)
        let url = newLinkURL.trimmingCharacters(in: .whitespaces)
        guard newLinkIssue == nil else { return }
        
        vm.links[name] = url
        newLinkName = ""
        newLinkURL = ""
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if vm.draftSession.isFailing {
            ToolbarItem(placement: .primaryAction) {
                DraftNotSavedLabel()
            }
        }
        if vm.hasDraft {
            ToolbarItem(placement: .primaryAction) {
                DraftMenu(isShowingChanges: $showDiff) {
                    showDiscardDraftConfirm = true
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Toggle("Preview", systemImage: "eye", isOn: $showPreview)
                .help("Preview the rendered description")
            Button("Details", systemImage: inspectorSystemImage) {
                showInspector.toggle()
            }
            .help("Show or hide the project's details")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            SaveToolbarButton("Save", isSaving: vm.isSaving, isDisabled: !vm.canSave) {
                Task { await vm.save() }
            }
        }
    }
    
    private var inspectorSystemImage: String {
        #if os(macOS)
        "sidebar.right"
        #else
        "info.circle"
        #endif
    }
    
    // MARK: - Inspector
    
    private var inspectorContent: some View {
        Form {
            Section("Status") {
                Picker("Status", selection: $vm.status) {
                    Text("Active").tag(ProjectStatus.active)
                    Text("In Progress").tag(ProjectStatus.inProgress)
                    Text("Archived").tag(ProjectStatus.archived)
                }
                .pickerStyle(.menu)
                Toggle("Featured", isOn: $vm.featured)
            }
            
            Section("Dates") {
                // NOTE: - A new project shows today until a date is picked, and is created with the date shown.
                DatePicker(
                    "Created",
                    selection: Binding(
                        get: { vm.createdAt ?? .now },
                        set: { vm.createdAt = $0 }
                    ),
                    displayedComponents: .date
                )
                if let updatedAt = vm.updatedAt {
                    LabeledContent("Updated") {
                        Text(updatedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
            
            if case .edit = vm.mode {
                Section {
                    Button("Delete Project…", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .disabled(vm.isSaving || vm.loadState != .loaded)
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
    }
}

#Preview {
    NavigationStack {
        ProjectFormView(
            vm: ProjectFormViewModel(mode: .edit(id: ProjectDetail.sample.id), repo: TestProjectRepository(), mediaRepo: TestMediaRepository(), drafts: .temporary()),
            onSave: { _ in },
            onDelete: {}
        )
    }
}
