import SwiftUI
import PhotosUI

/// Shows a post's or project's hero image and lets the user pick a new one, held as `pendingHeroImage` until the editor saves.
struct HeroImageRow: View {
    @Binding private var heroImage: String
    @Binding private var pendingHeroImage: PendingImage?
    private let uploadsOn: String
    
    @State private var pickerItem: PhotosPickerItem?
    @State private var isImporting = false
    @State private var importError: PendingImage.ImportError?
    /// A small copy of the picked image, made once rather than decoding the full image on every update.
    @State private var pendingPreview: Image?
    
    /// - Parameter uploadsOn: When a picked image is uploaded, as the save button calls it ("save", "publish").
    init(heroImage: Binding<String>, pendingHeroImage: Binding<PendingImage?>, uploadsOn: String) {
        self._heroImage = heroImage
        self._pendingHeroImage = pendingHeroImage
        self.uploadsOn = uploadsOn
    }
    
    var body: some View {
        let hasHeroImage = pendingHeroImage != nil || !heroImage.isEmpty
        
        VStack(alignment: .leading, spacing: 8) {
            preview
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(maxWidth: 420)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    if isImporting {
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.thinMaterial)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    if pendingHeroImage != nil {
                        Text("Uploads on \(uploadsOn)")
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.thinMaterial, in: Capsule())
                            .padding(8)
                    }
                }
            
            HStack(spacing: 12) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(hasHeroImage ? "Replace" : "Choose Image")
                }
                .onChange(of: pickerItem) { _, item in
                    guard let item else { return }
                    
                    pickerItem = nil
                    importImage { () throws(PendingImage.ImportError) in try await PendingImage.load(from: item) }
                }
                
                #if os(macOS)
                Button("From Files…") {
                    guard let url = PendingImage.chooseFiles().first else { return }
                    
                    importImage { () throws(PendingImage.ImportError) in try await PendingImage.load(contentsOf: url) }
                }
                #endif
                
                Spacer(minLength: 0)
                
                if hasHeroImage {
                    Button("Remove", role: .destructive) {
                        pendingHeroImage = nil
                        heroImage = ""
                    }
                    .foregroundStyle(.red)
                }
            }
            .buttonStyle(.borderless)
            .font(.callout)
            .disabled(isImporting)
        }
        .onChange(of: pendingHeroImage, initial: true) {
            pendingPreview = pendingHeroImage?.thumbnail(maxPixelSize: 840).map { Image(decorative: $0, scale: 1) }
        }
        .errorAlert($importError)
    }
    
    /// Prepares the picked image for upload (converting formats the server can't), and shows why if it can't be used.
    private func importImage(_ load: @escaping () async throws(PendingImage.ImportError) -> PendingImage) {
        isImporting = true
        Task {
            do throws(PendingImage.ImportError) {
                pendingHeroImage = try await load()
            } catch {
                importError = error
            }
            isImporting = false
        }
    }
    
    @ViewBuilder
    private var preview: some View {
        if pendingHeroImage != nil, let pendingPreview {
            pendingPreview.resizable().aspectRatio(contentMode: .fill)
        } else if let heroURL = mediaURL(for: heroImage) {
            AsyncImage(url: heroURL) { phase in
                if case let .success(image) = phase {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholder(systemImage: phase.error == nil ? "photo" : "exclamationmark.triangle", text: phase.error == nil ? nil : "Couldn't load the image")
                }
            }
        } else {
            placeholder(systemImage: "photo", text: "No hero image")
        }
    }
    
    private func placeholder(systemImage: String, text: String?) -> some View {
        Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: systemImage)
                        .font(.title2)
                    if let text {
                        Text(text)
                            .font(.caption)
                    }
                }
                .foregroundStyle(.secondary)
            }
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
