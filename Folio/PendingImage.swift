import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// An image chosen in Photos or Files that hasn't been uploaded yet.
struct PendingImage: Equatable {
    var data: Data
    var mimeType: String
    var ext: String
    
    /// A unique file name to upload it as. The server converts every upload to WebP named after the file's base name.
    var uploadFileName: String {
        "\(UUID().uuidString).\(ext)"
    }
}

extension PendingImage {
    // MARK: - Functions
    
    /// Loads an image picked in Photos.
    static func load(from item: PhotosPickerItem) async -> PendingImage? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        
        let type = item.supportedContentTypes.first
        return PendingImage(
            data: data,
            mimeType: type?.preferredMIMEType ?? "image/jpeg",
            ext: type?.preferredFilenameExtension ?? "jpg"
        )
    }
    
    #if os(macOS)
    /// Loads an image file chosen in an open panel or dropped on the window.
    init?(contentsOf url: URL) {
        // NOTE: - Files from an open panel are readable without this, but dropped files may need it.
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        
        guard let data = try? Data(contentsOf: url) else { return nil }
        
        let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
        self.init(
            data: data,
            mimeType: UTType(filenameExtension: ext)?.preferredMIMEType ?? "image/jpeg",
            ext: ext
        )
    }
    
    /// Asks for image files with an open panel.
    ///
    /// > Warning: Use this rather than `.fileImporter`, which silently does nothing inside a `Form` on macOS.
    static func chooseFiles(allowsMultipleSelection: Bool = false) -> [PendingImage] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = allowsMultipleSelection
        guard panel.runModal() == .OK else { return [] }
        
        return panel.urls.compactMap(PendingImage.init(contentsOf:))
    }
    #endif
}
