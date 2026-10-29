import SwiftUI

struct PostListRow: View {
    private let post: PostPreview
    
    init(post: PostPreview) {
        self.post = post
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            MediaThumbnail(path: post.heroImage, placeholderSystemImage: "doc.text")
            
            VStack(alignment: .leading, spacing: 3) {
                Text(post.title)
                    .font(.headline)
                    .lineLimit(1)
                
                if !post.excerpt.isEmpty {
                    Text(post.excerpt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                details
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
    
    /// The date, reading time, series, and tags, like "Jun 25, 2026 · 7 min read · Swift 6 · #swift #concurrency".
    private var details: Text {
        let parts = [
            post.createdAt.formatted(date: .abbreviated, time: .omitted),
            "\(post.readingTime) min read",
            post.series
        ].compactMap { $0 }
        let summary = parts.joined(separator: " · ")
        
        guard !post.tags.isEmpty else { return Text(summary) }
        
        let tags = Text(post.tags.map { "#\($0)" }.joined(separator: " ")).foregroundStyle(.tint)
        return Text("\(summary) · \(tags)")
    }
}

#Preview {
    List {
        PostListRow(post: PostDetail.sample.preview)
    }
}
