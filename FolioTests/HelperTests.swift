import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Folio

@MainActor
@Suite
struct HelperTests {
    // MARK: - Slugs
    
    /// Regression test: slugs only replaced spaces, so "My App!" became the URL path "my-app!".
    @Test(arguments: [
        ("My App!", "my-app"),
        ("  Trek Point  ", "trek-point"),
        ("C++ & Swift", "c-swift"),
        ("Café Menu", "cafe-menu"),
        ("already-a-slug", "already-a-slug"),
        ("!!!", "")
    ])
    func slugs(input: String, expected: String) {
        #expect(input.slugified == expected)
    }
    
    /// Regression test: slugs the server rejects (`index`, `nav`, or over 100 characters) were accepted.
    @Test func slugsTheServerRejectsHaveIssues() {
        #expect(ContentRules.slugIssue(for: "Index") != nil)
        #expect(ContentRules.slugIssue(for: "nav") != nil)
        #expect(ContentRules.slugIssue(for: "nav", reservesNames: false) == nil)
        #expect(ContentRules.slugIssue(for: String(repeating: "a", count: 101)) != nil)
        #expect(ContentRules.slugIssue(for: "!!!") != nil)
        #expect(ContentRules.slugIssue(for: "My Post") == nil)
    }
    
    @Test func urlsAreCheckedLikeTheServer() {
        #expect(ContentRules.isAllowedURL("/media/projects/a/1. Launch.webp", schemes: .web))
        #expect(ContentRules.isAllowedURL("https://example.com", schemes: .web))
        #expect(!ContentRules.isAllowedURL("mailto:me@example.com", schemes: .web))
        #expect(ContentRules.isAllowedURL("mailto:me@example.com", schemes: .webOrMail))
        #expect(!ContentRules.isAllowedURL("//example.com/a", schemes: .web))
        #expect(!ContentRules.isAllowedURL("example.com", schemes: .web))
        #expect(!ContentRules.isAllowedURL("javascript:alert(1)", schemes: .webOrMail))
    }
    
    // MARK: - Update payloads
    
    /// Regression test: `nil` fields were left out of updates, and the server keeps a field that's left out, so they couldn't be cleared.
    @Test func postUpdateSendsNullForClearedFields() throws {
        let update = PostUpdate(title: "T", excerpt: "E", content: "C", tags: [], heroImage: nil, series: nil, createdAt: nil)
        let json = try encodedObject(update)
        
        #expect(json["heroImage"] is NSNull)
        #expect(json["series"] is NSNull)
        #expect(json["createdAt"] == nil)
        #expect(json["title"] as? String == "T")
    }
    
    @Test func projectUpdateSendsNullForClearedCategory() throws {
        let sample = ProjectDetail.sample
        let update = ProjectUpdate(title: sample.title, tagline: sample.tagline, description: sample.description, heroImage: "", category: nil, status: .inProgress, featured: false, techStack: [], links: [:], media: [], createdAt: .sampleDate)
        let json = try encodedObject(update)
        
        #expect(json["category"] is NSNull)
        #expect(json["heroImage"] as? String == "")
        #expect(json["status"] as? String == "in-progress")
        #expect(json["createdAt"] as? String == "2026-06-25T12:00:00Z")
    }
    
    /// Regression test: app pages were saved with the synthesized encoding, which leaves out `nil` contact fields, so the server kept the old ones.
    @Test func appPageUpdatesSendNullForClearedContactFields() throws {
        let policy = try encodedObject(AppPrivacyPolicyUpdate(appName: "A", lastUpdated: "2026-10-29", content: "", contactUrl: nil, contactText: nil))
        let support = try encodedObject(AppSupportUpdate(appName: "A", version: "1.0", subtitle: "", content: "", contactUrl: nil, contactText: nil))
        
        #expect(policy["contactUrl"] is NSNull)
        #expect(policy["contactText"] is NSNull)
        #expect(support["contactUrl"] is NSNull)
        #expect(support["contactText"] is NSNull)
    }
    
    private func encodedObject(_ value: some Encodable) throws -> [String: Any] {
        let processor = URLProcessor(baseURL: URL(string: "https://example.com")!, apiKey: "")
        let data = try processor.encode(value)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    
    // MARK: - Media URLs
    
    @Test func mediaURLsResolveAgainstTheBaseURL() {
        #expect(mediaURL(for: "/media/a.webp", baseURL: "https://example.com/") == URL(string: "https://example.com/media/a.webp"))
        #expect(mediaURL(for: "media/a.webp", baseURL: "https://example.com") == URL(string: "https://example.com/media/a.webp"))
        #expect(mediaURL(for: "https://cdn.example.com/a.webp", baseURL: "https://example.com") == URL(string: "https://cdn.example.com/a.webp"))
        #expect(mediaURL(for: "", baseURL: "https://example.com") == nil)
    }
    
    /// Regression test: thumbnails downloaded full-size images, though the server saves smaller copies beside them.
    @Test func thumbnailsUseTheServersSmallerCopies() {
        #expect(smallerMediaPath(for: "/media/posts/a/hero.webp", width: 640) == "/media/posts/a/hero.w640.webp")
        #expect(smallerMediaPath(for: "/media/projects/a/1. Launch.webp", width: 640) == "/media/projects/a/1. Launch.w640.webp")
        #expect(smallerMediaPath(for: "/media/posts/a/hero.w640.webp", width: 640) == nil)
        #expect(smallerMediaPath(for: "https://cdn.example.com/a.webp", width: 640) == nil)
        #expect(smallerMediaPath(for: "/media/posts/a/hero.jpg", width: 640) == nil)
    }
    
    @Test func markdownImagesResolveAgainstTheBaseURL() {
        let markdown = "![one](/media/one.webp) and ![two](https://cdn.example.com/two.webp)"
        
        #expect(resolveMarkdownImageURLs(markdown, baseURL: "https://example.com/") == "![one](https://example.com/media/one.webp) and ![two](https://cdn.example.com/two.webp)")
        #expect(resolveMarkdownImageURLs(markdown, baseURL: "") == markdown)
    }
    
    /// Regression test: image syntax shown as code (in a fenced block or inline code) was rewritten in the preview, and reference-style images weren't resolved.
    @Test func markdownImagesInCodeAreLeftAlone() {
        let markdown = """
        Use `![alt](/media/x.webp)` for images.
        
        ```markdown
        ![alt](/media/in-fence.webp)
        ```
        
        ![hero][h]
        
        [h]: /media/hero.webp
        """
        let expected = """
        Use `![alt](/media/x.webp)` for images.
        
        ```markdown
        ![alt](/media/in-fence.webp)
        ```
        
        ![hero][h]
        
        [h]: https://example.com/media/hero.webp
        """
        
        #expect(resolveMarkdownImageURLs(markdown, baseURL: "https://example.com") == expected)
    }
    
    // MARK: - Reordering
    
    /// Regression test: dropping a gallery item on the next one left it where it was, and nothing could be moved to the end.
    @Test func droppingAnItemTakesTheTargetsPlace() {
        struct Item: Identifiable, Equatable { let id: String }
        let a = Item(id: "a"), b = Item(id: "b"), c = Item(id: "c")
        
        var items = [a, b, c]
        items.move(id: "a", onto: "b")
        #expect(items == [b, a, c])
        
        items = [a, b, c]
        items.move(id: "a", onto: "c")
        #expect(items == [b, c, a])
        
        items = [a, b, c]
        items.move(id: "c", onto: "a")
        #expect(items == [c, a, b])
        
        items = [a, b, c]
        let movedUp = items.move(id: "b", by: -1)
        let movedPastTheTop = items.move(id: "b", by: -1)
        #expect(movedUp)
        #expect(!movedPastTheTop)
        #expect(items == [b, a, c])
    }
    
    // MARK: - Dates
    
    /// Regression test: a date-only value was read as an instant in the device's time zone, so in Denver an evening "today" was saved as tomorrow.
    @Test func calendarDaysAreTheLocalDayAtMidnightUTC() throws {
        let denver = try #require(TimeZone(identifier: "America/Denver"))
        // 9 pm on October 29 in Denver is already October 30 in UTC.
        let evening = try #require(ISO8601DateFormatter().date(from: "2026-10-30T03:00:00Z"))
        
        #expect(AppPrivacyPolicyEditorViewModel.dateFormatter.string(from: evening.calendarDay(in: denver)) == "2026-10-29")
        #expect(evening.calendarDay(in: denver) == ISO8601DateFormatter().date(from: "2026-10-29T00:00:00Z"))
    }
    
    // MARK: - Image import
    
    /// Regression test: iPhone photos (HEIC) and other formats the server can't convert were uploaded as they were, and the server rejected them with 415.
    @Test func imagesTheServerCannotConvertBecomeJPEG() async throws {
        let tiff = try makeImage(type: .tiff)
        let converted = try await PendingImage.prepare(tiff)
        
        #expect(converted.mimeType == "image/jpeg")
        #expect(converted.ext == "jpg")
        
        let png = try makeImage(type: .png)
        let kept = try await PendingImage.prepare(png)
        
        #expect(kept.mimeType == "image/png")
        #expect(kept.data == png)
    }
    
    /// Regression test: images that couldn't be read were silently skipped.
    @Test func unreadableImagesThrow() async {
        await #expect(throws: PendingImage.ImportError.self) {
            _ = try await PendingImage.prepare(Data("not an image".utf8))
        }
    }
    
    private func makeImage(type: UTType) throws -> Data {
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }
    
    @Test func apiURLsJoinTheirComponents() {
        let processor = URLProcessor(baseURL: URL(string: "https://example.com")!, apiKey: "")
        
        #expect(processor.apiURL("apps", "trekpoint", "privacy-policy").absoluteString == "https://example.com/api/apps/trekpoint/privacy-policy")
    }
    
    // MARK: - Changed lines
    
    @Test func changedLinesAreHighlighted() {
        let ranges = computeChangedLineRanges(from: "one\ntwo\nthree", to: "one\nTWO\nthree\nfour")
        
        #expect(ranges == [NSRange(location: 4, length: 3), NSRange(location: 14, length: 4)])
    }
    
    @Test func nothingIsHighlightedWithoutABaseline() {
        #expect(computeChangedLineRanges(from: "", to: "new").isEmpty)
    }
    
    // MARK: - Unused files
    
    @Test func onlyUnusedFilesInTheItemsFolderAreDeleted() async {
        let mediaRepo = TestMediaRepository()
        let result = await mediaRepo.deleteUnusedFiles(
            previous: [
                "/media/posts/a/removed.webp",
                "/media/posts/a/kept.webp",
                "/media/posts/a/in-text.webp",
                "/media/posts/b/other-post.webp",
                ""
            ],
            current: ["/media/posts/a/kept.webp"],
            text: "![](/media/posts/a/in-text.webp)",
            context: .posts,
            id: "a"
        )
        
        #expect(mediaRepo.deletedFiles == ["/media/posts/a/removed.webp"])
        #expect(result.failed.isEmpty)
    }
}
