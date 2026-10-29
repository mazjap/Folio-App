import SwiftUI

extension View {
    // MARK: - Functions
    
    /// Shows `error` in an alert, and clears it when the alert is dismissed.
    func errorAlert<E: LocalizedError>(_ error: Binding<E?>) -> some View {
        alert(
            "Error",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error.wrappedValue?.localizedDescription ?? "")
        }
    }
    
    /// Shows `error` in an alert, and clears it when the alert is dismissed. For view models whose errors come from more than one source (the server, drafts on disk).
    func errorAlert(_ error: Binding<(any LocalizedError)?>) -> some View {
        alert(
            "Error",
            isPresented: Binding(
                get: { error.wrappedValue != nil },
                set: { if !$0 { error.wrappedValue = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error.wrappedValue?.localizedDescription ?? "")
        }
    }
}
