import SwiftUI
import PhotosUI

// MARK: - Toolbar

/// Formatting buttons for a `MarkdownEditorView`, sent to it through its `pendingAction`, followed by `accessory`.
struct MarkdownToolbar<Accessory: View>: View {
    @Binding private var pendingAction: EditorAction?
    private let accessory: Accessory
    
    init(pendingAction: Binding<EditorAction?>, @ViewBuilder accessory: () -> Accessory) {
        self._pendingAction = pendingAction
        self.accessory = accessory()
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                button(MarkdownToolbarLabel(systemImage: "bold"), title: "Bold", action: .wrap(prefix: "**", suffix: "**", placeholder: "text"))
                button(MarkdownToolbarLabel(systemImage: "italic"), title: "Italic", action: .wrap(prefix: "_", suffix: "_", placeholder: "text"))
                button(MarkdownToolbarLabel(systemImage: "chevron.left.forwardslash.chevron.right"), title: "Code", action: .wrap(prefix: "`", suffix: "`", placeholder: "code"))
                MarkdownToolbarDivider()
                button(MarkdownToolbarLabel("H1"), title: "Heading 1", action: .prependLine("# "))
                button(MarkdownToolbarLabel("H2"), title: "Heading 2", action: .prependLine("## "))
                button(MarkdownToolbarLabel("H3"), title: "Heading 3", action: .prependLine("### "))
                MarkdownToolbarDivider()
                button(MarkdownToolbarLabel(systemImage: "link"), title: "Link", action: .wrap(prefix: "[", suffix: "](url)", placeholder: "text"))
                button(MarkdownToolbarLabel(systemImage: "minus"), title: "Horizontal Rule", action: .insertText("\n\n---\n\n"))
                accessory
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .tint(.primary)
        }
        .scrollClipDisabled()
    }
    
    private func button(_ label: MarkdownToolbarLabel, title: String, action: EditorAction) -> some View {
        Button {
            pendingAction = action
        } label: {
            label
        }
        .buttonStyle(.borderless)
        .help(title)
        .accessibilityLabel(title)
    }
}

extension MarkdownToolbar where Accessory == EmptyView {
    init(pendingAction: Binding<EditorAction?>) {
        self.init(pendingAction: pendingAction) { EmptyView() }
    }
}

// MARK: - Label

/// The look of a markdown toolbar item: a symbol or short text in a fixed-size square, for accessories that match the formatting buttons.
struct MarkdownToolbarLabel: View {
    private let text: String?
    private let systemImage: String?
    
    /// The smallest a toolbar item is: compact for a pointer on macOS, and a comfortable touch target on iOS.
    #if os(macOS)
    private nonisolated static let minimumSize: CGFloat = 28
    #else
    private nonisolated static let minimumSize: CGFloat = 44
    #endif
    
    nonisolated init(_ text: String) {
        self.text = text
        self.systemImage = nil
    }
    
    nonisolated init(systemImage: String) {
        self.text = nil
        self.systemImage = systemImage
    }
    
    var body: some View {
        Group {
            if let systemImage {
                Image(systemName: systemImage)
            } else if let text {
                Text(text)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
            }
        }
        .frame(minWidth: Self.minimumSize, minHeight: Self.minimumSize)
        .contentShape(Rectangle())
    }
}

/// Separates groups of markdown toolbar items.
struct MarkdownToolbarDivider: View {
    var body: some View {
        Divider()
            .frame(height: 18)
            .padding(.horizontal, 4)
    }
}

// MARK: - Insert image

/// Buttons that pick an image from Photos (and Files on macOS) and hand it to `onPick`, which uploads it and inserts it.
struct InsertImageButtons: View {
    private let isEnabled: Bool
    private let onPick: (PendingImage) async -> Void
    
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var importError: PendingImage.ImportError?
    
    init(isEnabled: Bool, onPick: @escaping (PendingImage) async -> Void) {
        self.isEnabled = isEnabled
        self.onPick = onPick
    }
    
    var body: some View {
        MarkdownToolbarDivider()
        
        PhotosPicker(selection: $pickerItem, matching: .images) {
            MarkdownToolbarLabel(systemImage: "photo")
        }
        .buttonStyle(.borderless)
        .help(isEnabled ? "Insert Image from Photos" : "Enter an ID before adding images")
        .accessibilityLabel("Insert Image from Photos")
        .disabled(!isEnabled || isImporting)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            
            pickerItem = nil
            importImage { () throws(PendingImage.ImportError) in try await PendingImage.load(from: item) }
        }
        .errorAlert($importError)
        
        #if os(macOS)
        Button {
            guard let url = PendingImage.chooseFiles().first else { return }
            
            importImage { () throws(PendingImage.ImportError) in try await PendingImage.load(contentsOf: url) }
        } label: {
            MarkdownToolbarLabel(systemImage: "folder")
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Insert Image from Files")
        .help(isEnabled ? "Insert Image from Files" : "Enter an ID before adding images")
        .disabled(!isEnabled || isImporting)
        #endif
        
        if isImporting {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Adding image")
        }
    }
    
    /// Prepares the picked image (converting formats the server can't), then hands it to `onPick` to upload. Shows why if it can't be used.
    private func importImage(_ load: @escaping () async throws(PendingImage.ImportError) -> PendingImage) {
        isImporting = true
        Task {
            do throws(PendingImage.ImportError) {
                await onPick(try await load())
            } catch {
                importError = error
            }
            isImporting = false
        }
    }
}

#Preview {
    @Previewable @State var pendingAction: EditorAction?
    
    MarkdownToolbar(pendingAction: $pendingAction) {
        InsertImageButtons(isEnabled: true) { _ in }
    }
}
