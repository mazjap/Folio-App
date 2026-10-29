import SwiftUI
import PhotosUI

/// A project's gallery: drag to reorder, edit captions, remove, and add images through `onAdd`, which uploads them.
struct MediaManagerView: View {
    @Binding private var media: [MediaItem]
    private let isUploadEnabled: Bool
    private let isUploading: Bool
    private let onAdd: ([PendingImage]) async -> Void
    
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isImporting = false
    @State private var importError: PendingImage.ImportError?
    
    init(media: Binding<[MediaItem]>, isUploadEnabled: Bool, isUploading: Bool, onAdd: @escaping ([PendingImage]) async -> Void) {
        self._media = media
        self.isUploadEnabled = isUploadEnabled
        self.isUploading = isUploading
        self.onAdd = onAdd
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if media.isEmpty {
                Text("No images yet. Add some to show a gallery on the project's page.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach($media) { $item in
                    MediaItemRow(
                        item: $item,
                        canMoveUp: item.id != media.first?.id,
                        canMoveDown: item.id != media.last?.id,
                        onMove: { offset in
                            withAnimation { media.move(id: item.id, by: offset) }
                        },
                        onRemove: {
                            withAnimation { media.removeAll { $0.id == item.id } }
                        }
                    )
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
                    
                    pickerItems = []
                    importAndAdd(items) { item throws(PendingImage.ImportError) in try await PendingImage.load(from: item) }
                }
                
                #if os(macOS)
                Button("Add from Files", systemImage: "folder") {
                    let urls = PendingImage.chooseFiles(allowsMultipleSelection: true)
                    importAndAdd(urls) { url throws(PendingImage.ImportError) in try await PendingImage.load(contentsOf: url) }
                }
                #endif
                
                if isImporting || isUploading {
                    ProgressView()
                        .controlSize(.small)
                    Text(isImporting ? "Preparing…" : "Uploading…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            .disabled(!isUploadEnabled || isUploading || isImporting)
            
            if !isUploadEnabled {
                Text("Enter an ID before adding media.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .dropDestination(for: URL.self) { urls, _ in
            guard isUploadEnabled, !isUploading, !isImporting, !urls.isEmpty else { return false }
            
            importAndAdd(urls) { url throws(PendingImage.ImportError) in try await PendingImage.load(contentsOf: url) }
            return true
        }
        #endif
        .errorAlert($importError)
    }
    
    /// Prepares each source for upload (converting formats the server can't), then uploads the ones that worked. Shows why any couldn't be added.
    private func importAndAdd<Source>(_ sources: [Source], load: @escaping (Source) async throws(PendingImage.ImportError) -> PendingImage) {
        guard !sources.isEmpty else { return }
        
        isImporting = true
        Task {
            var images: [PendingImage] = []
            for source in sources {
                do throws(PendingImage.ImportError) {
                    images.append(try await load(source))
                } catch {
                    importError = error
                }
            }
            isImporting = false
            await onAdd(images)
        }
    }
    
    private func move(_ droppedID: String?, onto targetID: String) -> Bool {
        guard let droppedID else { return false }
        
        var reordered = media
        guard reordered.move(id: droppedID, onto: targetID) else { return false }
        
        withAnimation { media = reordered }
        return true
    }
}

// MARK: - Row

private struct MediaItemRow: View {
    @Binding private var item: MediaItem
    private let canMoveUp: Bool
    private let canMoveDown: Bool
    private let onMove: (Int) -> Void
    private let onRemove: () -> Void
    
    /// - Parameter onMove: Moves the item up (`-1`) or down (`1`).
    init(item: Binding<MediaItem>, canMoveUp: Bool, canMoveDown: Bool, onMove: @escaping (Int) -> Void, onRemove: @escaping () -> Void) {
        self._item = item
        self.canMoveUp = canMoveUp
        self.canMoveDown = canMoveDown
        self.onMove = onMove
        self.onRemove = onRemove
    }
    
    private var fileName: String {
        (item.url as NSString).lastPathComponent
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .frame(width: 16)
            
            MediaThumbnail(path: item.url, placeholderSystemImage: item.type == .video ? "video" : "photo", size: 56)
            
            VStack(alignment: .leading, spacing: 2) {
                TextField("Caption", text: Binding(
                    get: { item.caption ?? "" },
                    set: { item.caption = $0.isEmpty ? nil : $0 }
                ), prompt: Text("Add a caption"))
                .textFieldStyle(.plain)
                Text(fileName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            
            Spacer()
            
            Button("Remove \(fileName)", systemImage: "xmark.circle.fill", role: .destructive, action: onRemove)
                .labelStyle(.iconOnly)
                .foregroundStyle(.tertiary)
                .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Move Up", systemImage: "arrow.up") { onMove(-1) }
                .disabled(!canMoveUp)
            Button("Move Down", systemImage: "arrow.down") { onMove(1) }
                .disabled(!canMoveDown)
            Divider()
            Button("Remove", systemImage: "trash", role: .destructive, action: onRemove)
        }
        .accessibilityAction(named: "Move Up") { if canMoveUp { onMove(-1) } }
        .accessibilityAction(named: "Move Down") { if canMoveDown { onMove(1) } }
    }
}

#Preview {
    @Previewable @State var media = ProjectDetail.sample.media
    
    Form {
        MediaManagerView(media: $media, isUploadEnabled: true, isUploading: false) { _ in }
    }
    .formStyle(.grouped)
}
