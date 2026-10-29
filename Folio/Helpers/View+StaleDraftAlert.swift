import SwiftUI

extension View {
    // MARK: - Functions
    
    /// Asks whether to keep a draft that was started from an older version than the server's, since publishing it would undo the server's newer changes.
    /// - Parameters:
    ///   - itemKind: What's being edited, like "post".
    ///   - isLegacy: Whether the draft was saved before drafts were kept apart by environment, so it may come from the other server.
    func staleDraftAlert(isPresented: Binding<Bool>, itemKind: String, isLegacy: Bool = false, onKeep: @escaping () -> Void, onDiscard: @escaping () -> Void) -> some View {
        alert(isLegacy ? "Keep this older draft?" : "This \(itemKind) changed since your draft was saved", isPresented: isPresented) {
            Button("Keep Draft", action: onKeep)
            Button("Discard Draft", role: .destructive, action: onDiscard)
        } message: {
            if isLegacy {
                Text("This draft was saved before Folio kept Development and Production drafts apart, so it may have been started on the other server. Keeping it lets you publish it here.")
            } else {
                Text("Publishing your draft will undo the newer changes on the server. Discarding it shows the current version.")
            }
        }
    }
}
