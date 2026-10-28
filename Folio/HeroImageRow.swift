import SwiftUI
import PhotosUI

/// Shows a post's or project's hero image and lets the user pick a new one, held as `pendingHeroImage` until the editor saves.
struct HeroImageRow: View {
    @Binding private var heroImage: String
    @Binding private var pendingHeroImage: PendingImage?
    private let uploadsOn: String
    
    @State private var pickerItem: PhotosPickerItem?
    
    /// - Parameter uploadsOn: When a picked image is uploaded, as the save button calls it ("save", "publish").
    init(heroImage: Binding<String>, pendingHeroImage: Binding<PendingImage?>, uploadsOn: String) {
        self._heroImage = heroImage
        self._pendingHeroImage = pendingHeroImage
        self.uploadsOn = uploadsOn
    }
    
    var body: some View {
        let hasHeroImage = pendingHeroImage != nil || !heroImage.isEmpty
        
        if pendingHeroImage != nil {
            Label("Image selected · uploads on \(uploadsOn)", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        } else if let heroURL = mediaURL(for: heroImage) {
            AsyncImage(url: heroURL) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        
        HStack(spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(hasHeroImage ? "Change Hero Image" : "Set Hero Image", systemImage: "photo.badge.plus")
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                
                Task {
                    if let image = await PendingImage.load(from: item) {
                        pendingHeroImage = image
                    }
                    pickerItem = nil
                }
            }
            
            if hasHeroImage {
                Spacer()
                
                Button("Clear", role: .destructive) {
                    pendingHeroImage = nil
                    heroImage = ""
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }
        }
        
        #if os(macOS)
        Button("Select from Files…") {
            if let image = PendingImage.chooseFiles().first {
                pendingHeroImage = image
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        #endif
    }
}

#Preview {
    @Previewable @State var heroImage = ""
    @Previewable @State var pendingHeroImage: PendingImage?
    
    Form {
        HeroImageRow(heroImage: $heroImage, pendingHeroImage: $pendingHeroImage, uploadsOn: "save")
    }
    .formStyle(.grouped)
}
