import SwiftUI

/// The editor toolbar's menu for an unpublished draft: highlight the lines that changed (macOS only), or discard it.
struct DraftMenu: View {
    private let isShowingChanges: Binding<Bool>?
    private let onDiscard: () -> Void
    
    /// - Parameter isShowingChanges: Whether changed lines are highlighted, or `nil` for editors that can't highlight them.
    init(isShowingChanges: Binding<Bool>? = nil, onDiscard: @escaping () -> Void) {
        self.isShowingChanges = isShowingChanges
        self.onDiscard = onDiscard
    }
    
    var body: some View {
        Menu {
            // NOTE: - Only macOS's editor can highlight lines, and only added or changed ones: deleted lines have nothing to highlight.
            #if os(macOS)
            if let isShowingChanges {
                Toggle("Highlight Changed Lines", systemImage: "highlighter", isOn: isShowingChanges)
                
                Divider()
            }
            #endif
            
            Button("Discard Draft…", systemImage: "arrow.uturn.backward", role: .destructive, action: onDiscard)
        } label: {
            Label("Unpublished Changes", systemImage: "pencil.and.outline")
        }
        .help("This has unpublished changes")
    }
}

#Preview {
    @Previewable @State var isShowingChanges = false
    
    NavigationStack {
        Text("Editor")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    DraftMenu(isShowingChanges: $isShowingChanges) {}
                }
            }
    }
}
