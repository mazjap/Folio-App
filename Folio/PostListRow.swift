import SwiftUI

struct PostListRow: View {
    let post: PostPreview

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let hero = post.heroImage, let url = mediaURL(for: hero) {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.15))
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(post.excerpt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .imageScale(.small)
                    Text("\(post.readingTime) min read")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let series = post.series {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(series)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !post.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 4) {
                            ForEach(post.tags, id: \.self) { tag in
                                Text(tag)
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.tint.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
