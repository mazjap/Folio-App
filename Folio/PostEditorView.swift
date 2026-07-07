import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import Textual

struct PostEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State var vm: PostEditorViewModel
    var onSave: (PostPreview) -> Void
    var onDelete: () -> Void

    @State private var showInspector = true
    @State private var showPreview = false
    @State private var showDeleteConfirm = false
    @State private var showDiscardDraftConfirm = false
    @State private var showDiff = false
    @State private var diffRanges: [NSRange] = []
    @State private var heroPickerItem: PhotosPickerItem?
    @State private var inlinePickerItem: PhotosPickerItem?
    @State private var showHeroFileImporter = false
    @State private var showInlineFileImporter = false

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
        .onDisappear { if !vm.deleted { vm.saveDraft() } }
        .onChange(of: showDiff) {
            diffRanges = showDiff ? vm.computeDiffRanges() : []
        }
        .onChange(of: vm.content) {
            guard showDiff else { return }
            diffRanges = vm.computeDiffRanges()
        }
        .onChange(of: vm.hasDraft) {
            if !vm.hasDraft { showDiff = false; diffRanges = [] }
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
        .fileImporter(isPresented: $showInlineFileImporter, allowedContentTypes: [.image]) { result in
            if let url = try? result.get() { Task { await loadInlineFromFileURL(url) } }
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
            editorWithToolbar
        }
    }

    private var editorWithToolbar: some View {
        VStack(spacing: 0) {
            markdownToolbar
            Divider()
            MarkdownEditorView(text: $vm.content, pendingAction: $vm.pendingAction, highlightRanges: (showDiff && vm.hasDraft) ? diffRanges : [])
        }
    }

    // MARK: - Markdown toolbar

    private var markdownToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                markdownButton(label: "B", title: "Bold") { vm.pendingAction = .wrap(prefix: "**", suffix: "**", placeholder: "text") }
                markdownButton(label: "I", title: "Italic") { vm.pendingAction = .wrap(prefix: "_", suffix: "_", placeholder: "text") }
                markdownButton(label: "` `", title: "Code") { vm.pendingAction = .wrap(prefix: "`", suffix: "`", placeholder: "code") }
                Divider().frame(height: 20)
                markdownButton(label: "H1", title: "Heading 1") { vm.pendingAction = .prependLine("# ") }
                markdownButton(label: "H2", title: "Heading 2") { vm.pendingAction = .prependLine("## ") }
                markdownButton(label: "H3", title: "Heading 3") { vm.pendingAction = .prependLine("### ") }
                Divider().frame(height: 20)
                markdownButton(label: "—", title: "Horizontal Rule") { vm.pendingAction = .insertText("\n\n---\n\n") }
                markdownButton(label: "[ ]", title: "Link") { vm.pendingAction = .wrap(prefix: "[", suffix: "](url)", placeholder: "text") }
                Divider().frame(height: 20)
                PhotosPicker(selection: $inlinePickerItem, matching: .images) {
                    Text("![ ]")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help("Insert Image from Photos")
                .onChange(of: inlinePickerItem) { _, item in
                    guard let item else { return }
                    Task {
                        await loadInlineFromPicker(item)
                        inlinePickerItem = nil
                    }
                }
                #if os(macOS)
                Button(action: { showInlineFileImporter = true }) {
                    Label("Image from Files", systemImage: "folder")
                        .labelStyle(.iconOnly)
                        .font(.system(size: 12))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .help("Insert Image from Files")
                #endif
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(.bar)
    }

    private func markdownButton(label: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .help(title)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Publish", systemImage: "square.and.arrow.up") {
                Task { await vm.save() }
            }
            .disabled(vm.title.isEmpty || vm.isSaving)
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
                heroImageRow
            }

            Section("Metadata") {
                TextField("Series", text: $vm.series, prompt: Text("Optional series name"))
                TagsField(tags: $vm.tags)
            }

            if let createdAt = vm.createdAt {
                Section("Dates") {
                    LabeledContent("Published") {
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

    @ViewBuilder
    private var heroImageRow: some View {
        if vm.pendingHeroImage != nil {
            Label("Image selected · uploads on publish", systemImage: "checkmark.circle.fill")
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
                    vm.pendingHeroImage != nil || !vm.heroImage.isEmpty ? "Change Image" : "Set Hero Image",
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

    // MARK: - Image upload helpers

    private func loadHeroFromPicker(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let utType = item.supportedContentTypes.first
        let mimeType = utType?.preferredMIMEType ?? "image/jpeg"
        let ext = utType?.preferredFilenameExtension ?? "jpg"
        vm.pendingHeroImage = PendingImage(data: data, mimeType: mimeType, ext: ext)
        heroPickerItem = nil
    }

    private func loadInlineFromPicker(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        let utType = item.supportedContentTypes.first
        let mimeType = utType?.preferredMIMEType ?? "image/jpeg"
        let ext = utType?.preferredFilenameExtension ?? "jpg"
        await vm.uploadInlineImage(data: data, mimeType: mimeType, ext: ext)
    }

    private func loadHeroFromFileURL(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg"
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        vm.pendingHeroImage = PendingImage(data: data, mimeType: mimeType, ext: ext)
    }

    private func loadInlineFromFileURL(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }
        guard let data = try? Data(contentsOf: url) else { return }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "image/jpeg"
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        await vm.uploadInlineImage(data: data, mimeType: mimeType, ext: ext)
    }

}

// MARK: - Tags field

private struct TagsField: View {
    @Binding var tags: [String]
    @State private var newTag = ""

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
        // Return the proposed width unchanged — returning anything else tells the parent
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
