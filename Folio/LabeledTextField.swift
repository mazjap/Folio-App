import SwiftUI

/// A form text field that keeps its label visible once it has text.
///
/// macOS's grouped forms already show a text field's title beside it. On iOS the title is only a placeholder, so it's shown as a caption above the field instead.
struct LabeledTextField: View {
    private let title: String
    @Binding private var text: String
    private let prompt: String?
    private let axis: Axis
    
    init(_ title: String, text: Binding<String>, prompt: String? = nil, axis: Axis = .horizontal) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.axis = axis
    }
    
    var body: some View {
        #if os(macOS)
        TextField(title, text: $text, prompt: prompt.map(Text.init), axis: axis)
        #else
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: $text, prompt: Text(prompt ?? title), axis: axis)
        }
        #endif
    }
}

#Preview {
    @Previewable @State var title = "TrekPoint"
    @Previewable @State var tagline = ""
    
    Form {
        LabeledTextField("Title", text: $title)
        LabeledTextField("Tagline", text: $tagline, prompt: "One line about the project")
    }
    .formStyle(.grouped)
}
