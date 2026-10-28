import SwiftUI
import Textual

struct PostEditorView: View {
    @Environment(\.dismiss) private var dismiss
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
            headerFields
            Divider()
            editorOrPreview
        }
        .navigationTitle(vm.title.isEmpty ? "New Post" : vm.title)
        .toolbar { toolbarContent }
        .inspector(isPresented: $showInspector) {
            inspectorContent
        }
        .task { await vm.load() }
        .onDisappear { vm.saveDraftNow() }
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
        .staleDraftAlert(isPresented: $vm.isDraftStale, itemKind: "post", onKeep: vm.keepStaleDraft, onDiscard: vm.discardDraft)
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
    
    // MARK: - Header fields
    
    private var headerFields: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Title", text: $vm.title)
                .font(.title2.bold())
                .padding(.horizontal)
                .padding(.top, 12)
                .padding(.bottom, 6)
            
            if case .create = vm.mode {
                TextField("id-slug", text: $vm.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
                    #if !os(macOS)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    #endif
                    .disabled(vm.hasUploadedFiles)
                    .help(vm.hasUploadedFiles ? "Images are uploaded under this ID, so it can't change." : "")
            }
            
            TextField("Excerpt — shown in the post list", text: $vm.excerpt, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2...4)
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
        .background(.background)
    }
    
    // MARK: - Editor / Preview
    
    @ViewBuilder
    private var editorOrPreview: some View {
        if showPreview {
            ScrollView {
                StructuredText(markdown: vm.content.isEmpty ? "*Nothing to preview yet.*" : resolveMarkdownImageURLs(vm.content))
                    .textual.structuredTextStyle(.gitHub)
                    .padding()
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
            }
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Publish", systemImage: "square.and.arrow.up") {
                Task { await vm.save() }
            }
            .disabled(vm.title.isEmpty || vm.currentID.isEmpty || vm.isSaving)
            .keyboardShortcut("s", modifiers: .command)
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle("Preview", systemImage: showPreview ? "pencil" : "eye", isOn: $showPreview)
                .toggleStyle(.button)
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
                    .help("Highlight lines changed since last publish")
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
        ToolbarItem(placement: .status) {
            Text("\(vm.estimatedReadingTime) min read")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Inspector
    
    private var inspectorContent: some View {
        Form {
            Section("Hero Image") {
                HeroImageRow(heroImage: $vm.heroImage, pendingHeroImage: $vm.pendingHeroImage, uploadsOn: "publish")
            }
            
            Section("Metadata") {
                TextField("Series", text: $vm.series, prompt: Text("Optional series name"))
                TagsField(tags: $vm.tags)
            }
            
            if vm.createdAt != nil {
                Section("Dates") {
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
            }
            
            if case .edit = vm.mode {
                Section {
                    Button("Delete Post", role: .destructive) {
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
