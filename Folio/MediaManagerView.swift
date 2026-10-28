import SwiftUI
import PhotosUI

/// A project's gallery: drag to reorder, edit captions, remove, and add images through `onAdd`, which uploads them.
struct MediaManagerView: View {
    @Binding private var media: [MediaItem]
    private let isUploadEnabled: Bool
    private let isUploading: Bool
    private let onAdd: ([PendingImage]) async -> Void
    
    @State private var pickerItems: [PhotosPickerItem] = []
    
    init(media: Binding<[MediaItem]>, isUploadEnabled: Bool, isUploading: Bool, onAdd: @escaping ([PendingImage]) async -> Void) {
        self._media = media
        self.isUploadEnabled = isUploadEnabled
        self.isUploading = isUploading
        self.onAdd = onAdd
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if media.isEmpty {
                Text("No media attached.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach($media) { $item in
                    MediaItemRow(item: $item) {
                        withAnimation { media.removeAll { $0.id == item.id } }
                    }
                    .draggable(item.id)
                    .dropDestination(for: String.self) { droppedIDs, _ in
                        return move(droppedIDs.first, onto: item.id)
                    }
                }
            }
            
            HStack(spacing: 8) {
                PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                    Label("Add from Photos", systemImage: "photo")
                }
                .onChange(of: pickerItems) { _, items in
                    guard !items.isEmpty else { return }
                    
                    Task {
                        var images: [PendingImage] = []
                        for item in items {
                            if let image = await PendingImage.load(from: item) { images.append(image) }
                        }
                        pickerItems = []
                        await onAdd(images)
                    }
                }
                
                #if os(macOS)
                Button("Add from Files", systemImage: "folder") {
                    let images = PendingImage.chooseFiles(allowsMultipleSelection: true)
                    Task { await onAdd(images) }
                }
                #endif
                
                if isUploading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!isUploadEnabled || isUploading)
            
            if !isUploadEnabled {
                Text("Enter an ID before adding media.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .dropDestination(for: URL.self) { urls, _ in
            guard isUploadEnabled else { return false }
            
            let images = urls.compactMap(PendingImage.init(contentsOf:))
            Task { await onAdd(images) }
            return !images.isEmpty
        }
        #endif
    }
    
    private func move(_ droppedID: String?, onto targetID: String) -> Bool {
        guard let droppedID, droppedID != targetID,
              let from = media.firstIndex(where: { $0.id == droppedID }),
              let to = media.firstIndex(where: { $0.id == targetID })
        else { return false }
        
        withAnimation {
            let moved = media.remove(at: from)
            // Removing the item shifts the ones after it down by one.
            media.insert(moved, at: from < to ? to - 1 : to)
        }
        return true
    }
}

// MARK: - Row

private struct MediaItemRow: View {
    @Binding private var item: MediaItem
    private let onRemove: () -> Void
    
    init(item: Binding<MediaItem>, onRemove: @escaping () -> Void) {
        self._item = item
        self.onRemove = onRemove
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            
            AsyncImage(url: mediaURL(for: item.url)) { phase in
                if case let .success(image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.secondary.opacity(0.12)
                        .overlay {
                            if case .empty = phase {
                                ProgressView().scaleEffect(0.6)
                            } else {
                                Image(systemName: item.type == .video ? "video.fill" : "photo")
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(item.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                TextField("Caption (optional)", text: Binding(
                    get: { item.caption ?? "" },
                    set: { item.caption = $0.isEmpty ? nil : $0 }
                ))
                .font(.caption)
            }
            
            Spacer()
            
            Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
                .labelStyle(.iconOnly)
                .foregroundStyle(.red)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    @Previewable @State var media = ProjectDetail.sample.media
    
    Form {
        MediaManagerView(media: $media, isUploadEnabled: true, isUploading: false) { _ in }
    }
    .formStyle(.grouped)
}
