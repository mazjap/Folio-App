import SwiftUI

extension View {
    // MARK: - Functions
    
    /// Asks whether to keep a draft that was started from an older version than the server's, since publishing it would undo the server's newer changes.
    /// - Parameter itemKind: What's being edited, like "post".
    func staleDraftAlert(isPresented: Binding<Bool>, itemKind: String, onKeep: @escaping () -> Void, onDiscard: @escaping () -> Void) -> some View {
        alert("This \(itemKind) changed since your draft was saved", isPresented: isPresented) {
            Button("Keep Draft", action: onKeep)
            Button("Discard Draft", role: .destructive, action: onDiscard)
        } message: {
            Text("Publishing your draft will undo the newer changes on the server. Discarding it shows the current version.")
        }
    }
}
