import SwiftUI

/// What a content list shows in place of its rows: a spinner while it first loads, why it couldn't load, or that it's empty.
struct ContentListOverlay<Item: Identifiable & Equatable>: View where Item.ID == String {
    private let vm: ContentListViewModel<Item>
    private let noun: String
    private let systemImage: String
    private let emptyDescription: String
    private let newItemTitle: String
    
    /// - Parameters:
    ///   - noun: What the list holds, plural and capitalized ("Posts").
    ///   - newItemTitle: The title of the button that creates one ("New Post").
    init(vm: ContentListViewModel<Item>, noun: String, systemImage: String, emptyDescription: String, newItemTitle: String) {
        self.vm = vm
        self.noun = noun
        self.systemImage = systemImage
        self.emptyDescription = emptyDescription
        self.newItemTitle = newItemTitle
    }
    
    var body: some View {
        if vm.items.isEmpty {
            if vm.isLoading || !vm.hasFinishedLoading {
                ProgressView()
            } else if let loadError = vm.loadError {
                ContentUnavailableView {
                    Label("Couldn't Load \(noun)", systemImage: "exclamationmark.icloud")
                } description: {
                    Text(loadError.localizedDescription)
                } actions: {
                    Button("Try Again") {
                        Task { await vm.refresh() }
                    }
                }
            } else {
                ContentUnavailableView {
                    Label("No \(noun)", systemImage: systemImage)
                } description: {
                    Text(emptyDescription)
                } actions: {
                    Button(newItemTitle) {
                        vm.startCreating()
                    }
                }
            }
        }
    }
}
