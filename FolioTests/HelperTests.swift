import Foundation
import Testing
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
    
    @Test func markdownImagesResolveAgainstTheBaseURL() {
        let markdown = "![one](/media/one.webp) and ![two](https://cdn.example.com/two.webp)"
        
        #expect(resolveMarkdownImageURLs(markdown, baseURL: "https://example.com/") == "![one](https://example.com/media/one.webp) and ![two](https://cdn.example.com/two.webp)")
        #expect(resolveMarkdownImageURLs(markdown, baseURL: "") == markdown)
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
    
    @Test func onlyUnusedFilesInTheItemsFolderAreDeleted() async throws {
        let mediaRepo = TestMediaRepository()
        try await mediaRepo.deleteUnusedFiles(
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
    }
}
