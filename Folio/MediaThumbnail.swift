import SwiftUI

/// A square thumbnail of a media path, with a symbol in its place while it loads, when it fails, or when there's no image.
struct MediaThumbnail: View {
    private let path: String?
    private let placeholderSystemImage: String
    private let size: CGFloat
    
    init(path: String?, placeholderSystemImage: String, size: CGFloat = 52) {
        self.path = path
        self.placeholderSystemImage = placeholderSystemImage
        self.size = size
    }
    
    var body: some View {
        // NOTE: - The server's 640-pixel copy is plenty for a thumbnail. Older images may not have one yet, so a failure falls back to the original.
        AsyncImage(url: path.flatMap { smallerMediaPath(for: $0, width: 640) }.flatMap { mediaURL(for: $0) }) { phase in
            switch phase {
            case let .success(image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                original
            case .empty:
                if path.flatMap({ smallerMediaPath(for: $0, width: 640) }) == nil { original } else { placeholder }
            @unknown default:
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .accessibilityHidden(true)
    }
    
    private var original: some View {
        AsyncImage(url: path.flatMap { mediaURL(for: $0) }) { phase in
            if case let .success(image) = phase {
                image.resizable().aspectRatio(contentMode: .fill)
            } else {
                placeholder
            }
        }
    }
    
    private var placeholder: some View {
        Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                Image(systemName: placeholderSystemImage)
                    .font(.system(size: size * 0.38))
                    .foregroundStyle(.tertiary)
            }
    }
}

#Preview {
    HStack {
        MediaThumbnail(path: nil, placeholderSystemImage: "doc.text")
        MediaThumbnail(path: "/media/missing.webp", placeholderSystemImage: "folder")
    }
    .padding()
}
