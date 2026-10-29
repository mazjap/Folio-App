import SwiftUI

struct PostEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var vm: PostEditorViewModel
    private let onSave: (PostPreview) -> Void
    private let onDelete: () -> Void
    
    @State private var showInspector = true
    @State private var showPreview = false
    @State private var showDeleteConfirm = false
    @State private var showDiscardDraftConfirm = false
    @State private var showDiff = false
    @State private var diffRanges: [NSRange] = []
    
    init(vm: PostEditorViewModel, onSave: @escaping (PostPreview) -> Void, onDelete: @escaping () -> Void) {
        self._vm = State(initialValue: vm)
        self.onSave = onSave
        self.onDelete = onDelete
    }
    
    var body: some View {
        VStack(spacing: 0) {
            LoadProblemBanner(state: vm.loadState, itemKind: "post") {
                Task { await vm.load() }
            }
            headerFields
            Divider()
            editorOrPreview
        }
        .disabled(vm.loadState == .loading)
        .overlay {
            LoadStateOverlay(state: vm.loadState, itemKind: "post") {
                Task { await vm.load() }
            }
        }
        .navigationTitle(vm.title.isEmpty ? "New Post" : vm.title)
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
            diffRanges = showDiff ? vm.computeDiffRanges() : []
        }
        .onChange(of: vm.content) {
            guard showDiff else { return }
            
            diffRanges = vm.computeDiffRanges()
        }
        .onChange(of: vm.hasDraft) {
            if !vm.hasDraft {
                showDiff = false
                diffRanges = []
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
        .staleDraftAlert(isPresented: $vm.isDraftStale, itemKind: "post", isLegacy: vm.isDraftLegacy, onKeep: vm.keepStaleDraft, onDiscard: vm.discardDraft)
        .confirmationDialog("Delete “\(vm.title)”?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Post", role: .destructive) { Task { await vm.delete() } }
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
    
    // MARK: - Header fields
    
    private var headerFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $vm.title)
                .font(.title.bold())
                .textFieldStyle(.plain)
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 4)
            
            if case .create = vm.mode {
                TextField("url-slug", text: $vm.id)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textFieldStyle(.plain)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                    #if !os(macOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
                    .disabled(vm.hasUploadedFiles)
                    .help(vm.hasUploadedFiles ? "Images are uploaded under this ID, so it can't change." : "")
                
                if !vm.currentID.isEmpty {
                    Text("Published at /blog/\(vm.currentID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .padding(.bottom, 6)
                }
            }
            
            TextField("Excerpt, shown in the post list", text: $vm.excerpt, axis: .vertical)
                .font(.body)
                .foregroundStyle(.secondary)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal)
                .padding(.bottom, 12)
            
            ValidationIssuesView(issues: vm.loadState == .loaded ? vm.validationIssues : [])
                .padding(.horizontal)
                .padding(.bottom, vm.validationIssues.isEmpty ? 0 : 12)
        }
        .background(.background)
    }
    
    private var inspectorSystemImage: String {
        #if os(macOS)
        "sidebar.right"
        #else
        "info.circle"
        #endif
    }
    
    // MARK: - Editor / Preview
    
    @ViewBuilder
    private var editorOrPreview: some View {
        if showPreview {
            ScrollView {
                MarkdownPreview(markdown: vm.content)
                    .padding()
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: 0) {
                MarkdownToolbar(pendingAction: $vm.pendingAction) {
                    InsertImageButtons(isEnabled: vm.canUploadFiles) { image in
                        await vm.uploadInlineImage(image)
                    }
                }
                Divider()
                MarkdownEditorView(text: $vm.content, pendingAction: $vm.pendingAction, highlightRanges: (showDiff && vm.hasDraft) ? diffRanges : [])
                    .padding(.horizontal, 8)
            }
        }
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
                .help("Preview the rendered post")
            Button("Details", systemImage: inspectorSystemImage) {
                showInspector.toggle()
            }
            .help("Show or hide the post's details")
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            SaveToolbarButton("Publish", isSaving: vm.isSaving, isDisabled: !vm.canSave) {
                Task { await vm.save() }
            }
        }
    }
    
    // MARK: - Inspector
    
    private var inspectorContent: some View {
        Form {
            Section("Hero Image") {
                HeroImageRow(heroImage: $vm.heroImage, pendingHeroImage: $vm.pendingHeroImage, uploadsOn: "publish")
            }
            
            Section("Metadata") {
                LabeledTextField("Series", text: $vm.series, prompt: "None")
                TagsField(tags: $vm.tags)
                LabeledContent("Reading Time", value: "\(vm.estimatedReadingTime) min")
            }
            
            Section("Dates") {
                // NOTE: - A new post shows today until a date is picked, and is published with the date shown.
                DatePicker(
                    "Published",
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
                    Button("Delete Post…", role: .destructive) {
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

// MARK: - Tags field

private struct TagsField: View {
    @Binding private var tags: [String]
    @State private var newTag = ""
    
    init(tags: Binding<[String]>) {
        self._tags = tags
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !tags.isEmpty {
                FlowLayout(spacing: 4) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 2) {
                            Text(tag)
                                .font(.caption)
                            Button("Remove \(tag)", systemImage: "xmark.circle.fill") {
                                tags.removeAll { $0 == tag }
                            }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                            .buttonStyle(.plain)
                            .imageScale(.small)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.tint.opacity(0.12), in: Capsule())
                        .foregroundStyle(.tint)
                    }
                }
            }
            HStack {
                TextField("Add tag…", text: $newTag)
                    .onSubmit { addTag() }
                Button("Add", action: addTag)
                    .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
    
    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, !tags.contains(trimmed) else { return }
        
        tags.append(trimmed)
        newTag = ""
    }
}

// MARK: - Flow layout for tag chips

private struct FlowLayout: Layout {
    var spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // NOTE: - Return the proposed width unchanged. Returning anything else tells the parent
        // to re-offer a different width, which changes row counts, which changes the size
        // again, producing an infinite constraint loop on macOS.
        let availableWidth = proposal.replacingUnspecifiedDimensions().width
        let rows = computeRows(availableWidth: availableWidth, subviews: subviews)
        let height = rows.reduce(0.0) { total, row in
            let rowHeight = row.reduce(0.0) { max($0, $1.sizeThatFits(.unspecified).height) }
            return total + rowHeight + (total > 0 ? spacing : 0)
        }
        return CGSize(width: availableWidth, height: max(height, 0))
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(availableWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            let rowHeight = row.reduce(0.0) { max($0, $1.sizeThatFits(.unspecified).height) }
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }
    
    private func computeRows(availableWidth: CGFloat, subviews: Subviews) -> [[LayoutSubview]] {
        var rows: [[LayoutSubview]] = [[]]
        var rowWidth: CGFloat = 0
        for subview in subviews {
            let itemWidth = subview.sizeThatFits(.unspecified).width
            if rows[rows.count - 1].isEmpty {
                rowWidth = itemWidth
            } else if rowWidth + spacing + itemWidth > availableWidth {
                rows.append([])
                rowWidth = itemWidth
            } else {
                rowWidth += spacing + itemWidth
            }
            rows[rows.count - 1].append(subview)
        }
        return rows
    }
}

#Preview {
    NavigationStack {
        PostEditorView(
            vm: PostEditorViewModel(mode: .edit(id: PostDetail.sample.id), repo: TestPostRepository(), mediaRepo: TestMediaRepository(), drafts: .temporary()),
            onSave: { _ in },
            onDelete: {}
        )
    }
}
