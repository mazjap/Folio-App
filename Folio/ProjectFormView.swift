import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ProjectFormView: View {
    @Environment(\.dismiss) private var dismiss
    @State var vm: ProjectFormViewModel
    var onSave: (ProjectPreview) -> Void
    var onDelete: () -> Void

    @State private var showInspector = true
    @State private var showDeleteConfirm = false
    @State private var showDiscardDraftConfirm = false
    @State private var showDiff = false
    @State private var diffDescriptionRanges: [NSRange] = []
    @State private var newTag = ""
    @State private var newLinkName = ""
    @State private var newLinkURL = ""
    @State private var heroPickerItem: PhotosPickerItem?
    @State private var descriptionPickerItem: PhotosPickerItem?
    @State private var showHeroFileImporter = false
    @State private var showDescriptionFileImporter = false

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
                }
                TextField("Title", text: $vm.title)
                TextField("Tagline", text: $vm.tagline)
                TextField("Category", text: $vm.category, prompt: Text("iOS App, Web, macOS App…"))
                heroImageRow
            }

            Section("Description") {
                descriptionImageToolbar
                MarkdownEditorView(text: $vm.description, pendingAction: $vm.pendingDescriptionAction, highlightRanges: (showDiff && vm.hasDraft) ? diffDescriptionRanges : [])
                    .frame(minHeight: 160)
            }

            Section {
                techStackRows
            } header: {
                Text("Tech Stack")
            }

            Section {
                linksRows
            } header: {
                Text("Links")
            }

            Section("Media") {
                MediaManagerView(media: $vm.media, context: .projects, id: vm.currentID)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(vm.title.isEmpty ? "New Project" : vm.title)
        .toolbar { toolbarContent }
        .inspector(isPresented: $showInspector) {
            inspectorContent
        }
        .task { await vm.load() }
        .onDisappear { if !vm.deleted { vm.saveDraft() } }
        .onChange(of: showDiff) {
            diffDescriptionRanges = showDiff ? vm.computeDiffDescriptionRanges() : []
        }
        .onChange(of: vm.description) {
            guard showDiff else { return }
            diffDescriptionRanges = vm.computeDiffDescriptionRanges()
        }
        .onChange(of: vm.hasDraft) {
            if !vm.hasDraft { showDiff = false; diffDescriptionRanges = [] }
        }
        .onChange(of: vm.saved) { _, preview in
            if let preview { onSave(preview) }
        }
        .onChange(of: vm.deleted) { _, gone in
            if gone {
                onDelete()
                dismiss()
            }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.error != nil },
            set: { if !$0 { vm.error = nil } }
        )) {
            Button("OK", role: .cancel) { vm.error = nil }
        } message: {
            Text(vm.error?.localizedDescription ?? "")
        }
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
        .fileImporter(isPresented: $showHeroFileImporter, allowedContentTypes: [.image]) { result in
            if let url = try? result.get() { loadHeroFromFileURL(url) }
        }
        .fileImporter(isPresented: $showDescriptionFileImporter, allowedContentTypes: [.image]) { result in
            if let url = try? result.get() { Task { await loadDescriptionImageFromFileURL(url) } }
        }
    }

    // MARK: - Hero image row

    @ViewBuilder
    private var heroImageRow: some View {
        if vm.pendingHeroImage != nil {
            Label("Image selected · uploads on save", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else if let heroURL = mediaURL(for: vm.heroImage) {
            AsyncImage(url: heroURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        HStack(spacing: 8) {
            PhotosPicker(selection: $heroPickerItem, matching: .images) {
                Label(
                    vm.pendingHeroImage != nil || !vm.heroImage.isEmpty ? "Change Hero Image" : "Set Hero Image",
                    systemImage: "photo.badge.plus"
                )
            }
            .onChange(of: heroPickerItem) { _, item in
                guard let item else { return }
                Task { await loadHeroFromPicker(item) }
            }
            if vm.pendingHeroImage != nil || !vm.heroImage.isEmpty {
                Spacer()
                Button("Clear", role: .destructive) {
                    vm.pendingHeroImage = nil
                    vm.heroImage = ""
                    heroPickerItem = nil
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        #if os(macOS)
        Button("Select from Files…") { showHeroFileImporter = true }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
        #endif
    }

    // MARK: - Description image toolbar

    private var descriptionImageToolbar: some View {
        HStack(spacing: 6) {
            PhotosPicker(selection: $descriptionPickerItem, matching: .images) {
                Label("Insert Image", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .onChange(of: descriptionPickerItem) { _, item in
                guard let item else { return }
                Task {
                    await loadDescriptionImageFromPicker(item)
                    descriptionPickerItem = nil
                }
            }
            #if os(macOS)
            Button("From Files", systemImage: "folder") {
                showDescriptionFileImporter = true
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .controlSize(.small)
            #endif
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Tech stack

    private var techStackRows: some View {
        Group {
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
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !vm.techStack.contains(trimmed) else { return }
        vm.techStack.append(trimmed)
        newTag = ""
    }

    // MARK: - Links

    private var linksRows: some View {
        Group {
            ForEach(Array(vm.links.keys.sorted()), id: \.self) { key in
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
            .disabled(vm.title.isEmpty || vm.isSaving)
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

            if let createdAt = vm.createdAt {
                Section("Dates") {
                    LabeledContent("Created") {
                        Text(createdAt.formatted(date: .abbreviated, time: .omitted))
                    }
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

    // MARK: - Image upload helpers

    private func loadHeroFromPicker(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let utType = item.supportedContentTypes.first
        let mimeType = utType?.preferredMIMEType ?? "image/jpeg"
        let ext = utType?.preferredFilenameExtension ?? "jpg"
        vm.pendingHeroImage = PendingImage(data: data, mimeType: mimeType, ext: ext)
        heroPickerItem = nil
    }

    private func loadDescriptionImageFromPicker(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let utType = item.supportedContentTypes.first
        let mimeType = utType?.preferredMIMEType ?? "image/jpeg"
        let ext = utType?.preferredFilenameExtension ?? "jpg"
        await vm.uploadInlineImageToDescription(data: data, mimeType: mimeType, ext: ext)
    }

    private func loadHeroFromFileURL(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg"
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        vm.pendingHeroImage = PendingImage(data: data, mimeType: mimeType, ext: ext)
    }

    private func loadDescriptionImageFromFileURL(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg"
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        await vm.uploadInlineImageToDescription(data: data, mimeType: mimeType, ext: ext)
    }
}
