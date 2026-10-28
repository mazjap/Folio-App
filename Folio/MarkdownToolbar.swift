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
                button("B", title: "Bold", action: .wrap(prefix: "**", suffix: "**", placeholder: "text"))
                button("I", title: "Italic", action: .wrap(prefix: "_", suffix: "_", placeholder: "text"))
                button("` `", title: "Code", action: .wrap(prefix: "`", suffix: "`", placeholder: "code"))
                Divider().frame(height: 20)
                button("H1", title: "Heading 1", action: .prependLine("# "))
                button("H2", title: "Heading 2", action: .prependLine("## "))
                button("H3", title: "Heading 3", action: .prependLine("### "))
                Divider().frame(height: 20)
                button("—", title: "Horizontal Rule", action: .insertText("\n\n---\n\n"))
                button("[ ]", title: "Link", action: .wrap(prefix: "[", suffix: "](url)", placeholder: "text"))
                accessory
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .background(.bar)
    }
    
    private func button(_ label: String, title: String, action: EditorAction) -> some View {
        Button {
            pendingAction = action
        } label: {
            MarkdownToolbarLabel(label)
        }
        .buttonStyle(.plain)
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

/// The look of a markdown toolbar item, for accessories that match the formatting buttons.
struct MarkdownToolbarLabel: View {
    private let text: String
    
    nonisolated init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
    }
}

// MARK: - Insert image

/// Buttons that pick an image from Photos (and Files on macOS) and hand it to `onPick`, which uploads it and inserts it.
struct InsertImageButtons: View {
    private let isEnabled: Bool
    private let onPick: (PendingImage) async -> Void
    
    @State private var pickerItem: PhotosPickerItem?
    
    init(isEnabled: Bool, onPick: @escaping (PendingImage) async -> Void) {
        self.isEnabled = isEnabled
        self.onPick = onPick
    }
    
    var body: some View {
        Divider().frame(height: 20)
        
        PhotosPicker(selection: $pickerItem, matching: .images) {
            MarkdownToolbarLabel("![ ]")
        }
        .buttonStyle(.plain)
        .help(isEnabled ? "Insert Image from Photos" : "Enter an ID before adding images")
        .accessibilityLabel("Insert Image from Photos")
        .disabled(!isEnabled)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            
            Task {
                if let image = await PendingImage.load(from: item) {
                    await onPick(image)
                }
                pickerItem = nil
            }
        }
        
        #if os(macOS)
        Button("Insert Image from Files", systemImage: "folder") {
            guard let image = PendingImage.chooseFiles().first else { return }
            
            Task { await onPick(image) }
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 12))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .buttonStyle(.plain)
        .help(isEnabled ? "Insert Image from Files" : "Enter an ID before adding images")
        .disabled(!isEnabled)
        #endif
    }
}

#Preview {
    @Previewable @State var pendingAction: EditorAction?
    
    MarkdownToolbar(pendingAction: $pendingAction) {
        InsertImageButtons(isEnabled: true) { _ in }
    }
}
