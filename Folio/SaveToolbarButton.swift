import SwiftUI

/// An editor's primary toolbar button ("Save", "Publish"), drawn prominently, with a spinner in its place while saving.
struct SaveToolbarButton: View {
    private let title: String
    private let isSaving: Bool
    private let isDisabled: Bool
    private let action: () -> Void
    
    init(_ title: String, isSaving: Bool, isDisabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSaving = isSaving
        self.isDisabled = isDisabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Saving")
            } else {
                Text(title)
            }
        }
        .buttonStyle(.glassProminent)
        .disabled(isDisabled || isSaving)
        .keyboardShortcut("s", modifiers: .command)
    }
}

#Preview {
    NavigationStack {
        Text("Editor")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    SaveToolbarButton("Publish", isSaving: false, isDisabled: false) {}
                }
            }
    }
}
