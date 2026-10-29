import SwiftUI
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

/// An image chosen in Photos or Files that hasn't been uploaded yet, already in a format the server accepts.
nonisolated struct PendingImage: Equatable, Codable {
    var data: Data
    var mimeType: String
    var ext: String
    
    /// A unique file name to upload it as. The server converts every upload to WebP named after the file's base name.
    var uploadFileName: String {
        "\(UUID().uuidString).\(ext)"
    }
}

extension PendingImage {
    // MARK: - Import errors
    
    nonisolated enum ImportError: Error, LocalizedError {
        case unreadable
        case tooLarge(bytes: Int)
        case conversionFailed
        
        var errorDescription: String? {
            switch self {
            case .unreadable:
                "The image couldn't be read."
            case let .tooLarge(bytes):
                "The image is \(bytes.formatted(.byteCount(style: .file))), larger than the server's \(PendingImage.maxUploadSize.formatted(.byteCount(style: .file))) limit."
            case .conversionFailed:
                "The image couldn't be converted to JPEG for uploading."
            }
        }
    }
    
    // MARK: - Functions
    
    /// The largest file the server accepts.
    nonisolated static let maxUploadSize = 25 * 1024 * 1024
    
    /// Formats the server can convert to WebP. Anything else (HEIC, TIFF, …) is converted to JPEG first: prebuilt sharp can't decode HEIC, and iPhone photos usually are.
    nonisolated static let serverFormats: [UTType] = [.jpeg, .png, .webP, .gif, UTType("public.avif")].compactMap(\.self)
    
    /// Turns picked image data into an upload: kept as it is when the server can convert it, otherwise converted to JPEG, keeping its metadata (like orientation). Runs off the main actor, since conversion can take a while.
    @concurrent
    static func prepare(_ data: Data) async throws(ImportError) -> PendingImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let typeIdentifier = CGImageSourceGetType(source) as String?,
              let type = UTType(typeIdentifier),
              CGImageSourceGetCount(source) > 0
        else { throw .unreadable }
        
        let image: PendingImage
        if serverFormats.contains(type), let mimeType = type.preferredMIMEType {
            image = PendingImage(data: data, mimeType: mimeType, ext: type.preferredFilenameExtension ?? "jpg")
        } else {
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { throw .conversionFailed }
            
            CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw .conversionFailed }
            
            image = PendingImage(data: output as Data, mimeType: "image/jpeg", ext: "jpg")
        }
        
        guard image.data.count <= maxUploadSize else { throw .tooLarge(bytes: image.data.count) }
        
        return image
    }
    
    /// A copy no larger than `maxPixelSize` on its longest side, upright, for showing before it's uploaded.
    func thumbnail(maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
    
    /// Loads an image picked in Photos.
    static func load(from item: PhotosPickerItem) async throws(ImportError) -> PendingImage {
        let data: Data?
        do {
            data = try await item.loadTransferable(type: Data.self)
        } catch {
            throw .unreadable
        }
        guard let data else { throw .unreadable }
        
        return try await prepare(data)
    }
    
    #if os(macOS)
    /// Loads an image file chosen in an open panel or dropped on the window, off the main actor.
    @concurrent
    static func load(contentsOf url: URL) async throws(ImportError) -> PendingImage {
        // NOTE: - Files from an open panel are readable without this, but dropped files may need it.
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw .unreadable
        }
        return try await prepare(data)
    }
    
    /// Asks for image files with an open panel.
    ///
    /// > Warning: Use this rather than `.fileImporter`, which silently does nothing inside a `Form` on macOS.
    @MainActor
    static func chooseFiles(allowsMultipleSelection: Bool = false) -> [URL] {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = allowsMultipleSelection
        guard panel.runModal() == .OK else { return [] }
        
        return panel.urls
    }
    #endif
}
