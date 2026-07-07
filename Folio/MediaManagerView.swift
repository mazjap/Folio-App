import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MediaManagerView: View {
    @Binding var media: [MediaItem]
    let context: MediaContext
    let id: String

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var isUploading = false
    @State private var uploadError: String?

    #if os(macOS)
    @State private var showFileImporter = false
    #endif

    private let repo = MediaRepository()

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
                }
                .onMove { media.move(fromOffsets: $0, toOffset: $1) }
            }

            HStack(spacing: 8) {
                PhotosPicker(
                    selection: $pickerItems,
                    maxSelectionCount: 10,
                    matching: .any(of: [.images, .videos])
                ) {
                    Label("Add from Photos", systemImage: "photo")
                }
                .onChange(of: pickerItems) { _, items in
                    guard !items.isEmpty else { return }
                    Task { await uploadPhotoItems(items) }
                }

                #if os(macOS)
                Button("Add from Files", systemImage: "folder") {
                    showFileImporter = true
                }
                #endif

                if isUploading {
                    ProgressView()
                }
            }
            .buttonStyle(.bordered)

            if let err = uploadError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        #if os(macOS)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .video, .movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await uploadFileURLs(urls) }
            case .failure(let e):
                uploadError = e.localizedDescription
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await uploadFileURLs(urls) }
            return true
        }
        #endif
    }

    // MARK: - Upload helpers

    private func uploadPhotoItems(_ items: [PhotosPickerItem]) async {
        isUploading = true
        defer {
            isUploading = false
            pickerItems = []
        }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let utType = item.supportedContentTypes.first
            let mimeType = utType?.preferredMIMEType ?? "image/jpeg"
            let ext = utType?.preferredFilenameExtension ?? "jpg"
            let fileName = "\(UUID().uuidString).\(ext)"
            let mediaType: MediaType = utType?.conforms(to: .video) == true ? .video : .image
            await uploadData(data, fileName: fileName, mimeType: mimeType, mediaType: mediaType)
        }
    }

    #if os(macOS)
    private func uploadFileURLs(_ urls: [URL]) async {
        isUploading = true
        defer { isUploading = false }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let utType = UTType(filenameExtension: url.pathExtension)
            let mimeType = utType?.preferredMIMEType ?? "application/octet-stream"
            let mediaType: MediaType = utType?.conforms(to: .video) == true ? .video : .image
            await uploadData(data, fileName: url.lastPathComponent, mimeType: mimeType, mediaType: mediaType)
        }
    }
    #endif

    private func uploadData(_ data: Data, fileName: String, mimeType: String, mediaType: MediaType) async {
        do {
            let url = try await repo.upload(fileData: data, fileName: fileName, mimeType: mimeType, context: context, id: id)
            media.append(MediaItem(type: mediaType, url: url, caption: nil))
            uploadError = nil
        } catch {
            uploadError = error.localizedDescription
        }
    }
}

// MARK: - Row

private struct MediaItemRow: View {
    @Binding var item: MediaItem
    var onRemove: () -> Void

    @State private var isEditingCaption = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.type == .video ? "video.fill" : "photo.fill")
                .foregroundStyle(.secondary)
                .frame(width: 24)

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
