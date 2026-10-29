import SwiftUI

/// Covers an editor while its item loads, or when it couldn't load and there's no draft to show instead.
struct LoadStateOverlay: View {
    private let state: EditorLoadState
    private let itemKind: String
    private let onRetry: () -> Void
    
    /// - Parameter itemKind: What's being edited, like "post".
    init(state: EditorLoadState, itemKind: String, onRetry: @escaping () -> Void) {
        self.state = state
        self.itemKind = itemKind
        self.onRetry = onRetry
    }
    
    var body: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background.opacity(0.6))
        case let .failed(message, showsDraft: false):
            ContentUnavailableView {
                Label("Couldn't Load This \(itemKind.capitalized)", systemImage: "exclamationmark.icloud")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again", action: onRetry)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        case .loaded, .failed:
            EmptyView()
        }
    }
}

/// Explains above an editor that it's showing the item's saved draft because the server's version couldn't load, which can't be published until it does.
struct LoadProblemBanner: View {
    private let state: EditorLoadState
    private let itemKind: String
    private let onRetry: () -> Void
    
    /// - Parameter itemKind: What's being edited, like "post".
    init(state: EditorLoadState, itemKind: String, onRetry: @escaping () -> Void) {
        self.state = state
        self.itemKind = itemKind
        self.onRetry = onRetry
    }
    
    var body: some View {
        if case let .failed(message, showsDraft: true) = state {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.icloud")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Showing your saved draft")
                        .font(.callout.weight(.semibold))
                    Text("The \(itemKind) couldn't be loaded (\(message)). You can keep editing, and save once it loads.")
                        .font(.caption)
                }
                Spacer(minLength: 0)
                Button("Try Again", action: onRetry)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.15))
        }
    }
}

/// A toolbar warning that drafts aren't being saved to disk, so unpublished changes aren't protected.
struct DraftNotSavedLabel: View {
    var body: some View {
        Label("Draft Not Saved", systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .help("Folio couldn't save your draft on this device. Publish or copy your changes before closing.")
    }
}

#Preview {
    VStack {
        LoadProblemBanner(state: .failed(message: "The network connection was lost.", showsDraft: true), itemKind: "post") {}
        LoadStateOverlay(state: .failed(message: "The network connection was lost.", showsDraft: false), itemKind: "post") {}
    }
}
