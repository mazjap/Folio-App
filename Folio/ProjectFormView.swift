import SwiftUI

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ProjectFormViewModel
    private let onSave: (ProjectPreview) -> Void
    private let onDelete: () -> Void
    
    @State private var showInspector = true
    @State private var showDeleteConfirm = false
    @State private var showDiscardDraftConfirm = false
    @State private var showDiff = false
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
            Section("Details") {
                if case .create = vm.mode {
                    TextField("ID (slug)", text: $vm.id)
                        .textContentType(.none)
                        #if !os(macOS)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        #endif
                        .disabled(vm.hasUploadedFiles)
                        .help(vm.hasUploadedFiles ? "Images are uploaded under this ID, so it can't change." : "")
                }
                TextField("Title", text: $vm.title)
                TextField("Tagline", text: $vm.tagline)
                TextField("Category", text: $vm.category, prompt: Text("iOS App, Web, macOS App…"))
                HeroImageRow(heroImage: $vm.heroImage, pendingHeroImage: $vm.pendingHeroImage, uploadsOn: "save")
            }
            
            Section("Description") {
                MarkdownToolbar(pendingAction: $vm.pendingDescriptionAction) {
                    InsertImageButtons(isEnabled: vm.canUploadFiles) { image in
                        await vm.uploadInlineImageToDescription(image)
                    }
                }
                MarkdownEditorView(text: $vm.description, pendingAction: $vm.pendingDescriptionAction, highlightRanges: (showDiff && vm.hasDraft) ? diffDescriptionRanges : [])
                    .frame(minHeight: 160)
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
        .navigationTitle(vm.title.isEmpty ? "New Project" : vm.title)
        .toolbar { toolbarContent }
        .inspector(isPresented: $showInspector) {
            inspectorContent
        }
        .task { await vm.load() }
        .onDisappear { vm.saveDraftNow() }
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
        .staleDraftAlert(isPresented: $vm.isDraftStale, itemKind: "project", onKeep: vm.keepStaleDraft, onDiscard: vm.discardDraft)
        .confirmationDialog("Delete \"\(vm.title)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await vm.delete() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
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
                Button("Remove", systemImage: "minus.circle.fill", role: .destructive) {
                    vm.techStack.removeAll { $0 == tag }
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
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
                Text(key).bold()
                Spacer()
                Text(vm.links[key] ?? "").foregroundStyle(.secondary).lineLimit(1)
                Button("Remove", systemImage: "minus.circle.fill", role: .destructive) {
                    vm.links.removeValue(forKey: key)
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
                .buttonStyle(.plain)
            }
        }
        VStack(spacing: 8) {
            TextField("Link name (e.g. GitHub)", text: $newLinkName)
            TextField("URL", text: $newLinkURL, prompt: Text("https://…"))
                .textContentType(.URL)
                #if !os(macOS)
                .keyboardType(.URL)
                #endif
                .onSubmit { addLink() }
            Button("Add Link", action: addLink)
                .disabled(newLinkName.isEmpty || newLinkURL.isEmpty)
        }
    }
    
    private func addLink() {
        let name = newLinkName.trimmingCharacters(in: .whitespaces)
        let url = newLinkURL.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !url.isEmpty else { return }
        
        vm.links[name] = url
        newLinkName = ""
        newLinkURL = ""
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Save", systemImage: "square.and.arrow.up") {
                Task { await vm.save() }
            }
            .disabled(vm.title.isEmpty || vm.currentID.isEmpty || vm.isSaving)
            .keyboardShortcut("s", modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Inspector", systemImage: "sidebar.right") {
                showInspector.toggle()
            }
        }
        if vm.hasDraft {
            ToolbarItem(placement: .primaryAction) {
                Toggle("Show Changes", systemImage: "highlighter", isOn: $showDiff)
                    .toggleStyle(.button)
                    .help("Highlight lines changed since last save")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Discard Draft", systemImage: "arrow.counterclockwise") {
                    showDiscardDraftConfirm = true
                }
                .foregroundStyle(.orange)
                .help("Revert to last published version")
            }
        }
        if vm.isSaving {
            ToolbarItem(placement: .status) {
                ProgressView()
            }
        }
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
            
            if vm.createdAt != nil {
                Section("Dates") {
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
            }
            
            if case .edit = vm.mode {
                Section {
                    Button("Delete Project", role: .destructive) {
                        showDeleteConfirm = true
                    }
                    .keyboardShortcut(.delete, modifiers: .command)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Inspector")
        .inspectorColumnWidth(min: 200, ideal: 240, max: 320)
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
