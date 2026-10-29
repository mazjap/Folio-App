import SwiftUI
import Textual

/// Markdown rendered for review, with the server's relative image paths resolved so images load.
///
/// It's close to the published page, not identical: the site renders with its own Markdown components.
struct MarkdownPreview: View {
    private let markdown: String
    
    init(markdown: String) {
        self.markdown = markdown
    }
    
    var body: some View {
        StructuredText(markdown: markdown.isEmpty ? "*Nothing to preview yet.*" : resolveMarkdownImageURLs(markdown))
            .textual.structuredTextStyle(.gitHub)
            .frame(maxWidth: 720, alignment: .leading)
    }
}

#Preview {
    ScrollView {
        MarkdownPreview(markdown: "# Heading\n\nSome **bold** text and `code`.")
            .padding()
    }
}
