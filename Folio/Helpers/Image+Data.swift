import SwiftUI

extension Image {
    // MARK: - Functions
    
    /// An image decoded from file data, like a picked image that hasn't been uploaded.
    init?(imageData: Data) {
        #if os(macOS)
        guard let image = NSImage(data: imageData) else { return nil }
        self.init(nsImage: image)
        #else
        guard let image = UIImage(data: imageData) else { return nil }
        self.init(uiImage: image)
        #endif
    }
}
