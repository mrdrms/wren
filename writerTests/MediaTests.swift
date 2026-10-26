import Foundation
import Testing
@testable import writer

struct MediaTests {
    @Test func detectsMediaKinds() {
        #expect(MarkdownImage.kind(of: "assets/photo.png") == .image)
        #expect(MarkdownImage.kind(of: "assets/clip.MP4") == .video)
        #expect(MarkdownImage.kind(of: "https://cdn.example.com/a.webm?x=1") == .video)
        #expect(MarkdownImage.kind(of: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=10") == .youtube(id: "dQw4w9WgXcQ"))
        #expect(MarkdownImage.kind(of: "https://youtu.be/dQw4w9WgXcQ") == .youtube(id: "dQw4w9WgXcQ"))
        #expect(MarkdownImage.kind(of: "https://youtube.com/shorts/abcDEF12345") == .youtube(id: "abcDEF12345"))
        #expect(MarkdownImage.youTubeID("https://example.com/watch?v=dQw4w9WgXcQ") == nil)
    }

    @Test func resolvesRelativeAndRemotePaths() {
        let folder = URL(fileURLWithPath: "/tmp/blog")
        #expect(MarkdownImage.resolve("assets/a%20b.png", relativeTo: folder)?.path == "/tmp/blog/assets/a b.png")
        #expect(MarkdownImage.resolve("https://x.y/i.png", relativeTo: folder)?.absoluteString == "https://x.y/i.png")
    }

    @Test func rendersMediaAsHTML() {
        let html = MarkdownHTML.convert("![Cat](assets/cat.jpg)\n\n![Demo](assets/demo.mp4)\n\n![Talk](https://youtu.be/dQw4w9WgXcQ)")
        #expect(html.contains("<img src=\"assets/cat.jpg\" alt=\"Cat\">"))
        #expect(html.contains("<video controls preload=\"metadata\" src=\"assets/demo.mp4\" title=\"Demo\"></video>"))
        #expect(html.contains("https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"))
        MarkdownHTML.videosAsLinks = true
        defer { MarkdownHTML.videosAsLinks = false }
        #expect(MarkdownHTML.convert("![Demo](assets/demo.mp4)") == "<p><a href=\"assets/demo.mp4\">▶ Demo</a></p>")
    }

    @Test func embedsLocalImagesInHTML() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("assets"), withIntermediateDirectories: true)
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: folder.appendingPathComponent("assets/a.png"))
        let html = Exporter.embedMedia(in: "<img src=\"assets/a.png\" alt=\"\"><img src=\"https://x.y/b.png\">", folder: folder)
        #expect(html.contains("src=\"data:image/png;base64,iVBORw==\""))
        #expect(html.contains("src=\"https://x.y/b.png\""))
    }

    @Test func frontMatterIsMetadata() {
        let text = "---\ntitle: \"Hello, Blog\"\ndate: 2026-10-25\n---\n\n# Heading\nBody ![x](a.png) text."
        #expect(FrontMatter.strip(text) == "\n# Heading\nBody ![x](a.png) text.")
        #expect(LibraryStore.titleAndPreview(text: text, fallback: "f").0 == "Hello, Blog")
        #expect(!MarkdownHTML.convert(text).contains("title:"))
        #expect(TextStats.wordCount(MarkdownImage.stripForCounting(FrontMatter.strip(text))) == 3)
        #expect(FrontMatter.range(in: "---\nno closing fence") == nil)
        #expect(FrontMatter.make(title: "A \"quoted\" title").hasPrefix("---\ntitle: \"A \\\"quoted\\\" title\"\n"))
    }

    @Test func importsIntoAssetsFolder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = folder.appendingPathComponent("My Holiday Photo!.JPG")
        try Data([1, 2, 3]).write(to: source)
        let sheet = folder.appendingPathComponent("Post.md")
        let first = try ImageImporter.importImage(.file(source), for: sheet)
        let second = try ImageImporter.importImage(.file(source), for: sheet)
        #expect(first.path == "assets/my-holiday-photo.jpg")
        #expect(second.path == "assets/my-holiday-photo-2.jpg")
        #expect(first.alt == "My Holiday Photo!")
        let pasted = try ImageImporter.importImage(.data(Data([0]), ext: "png"), for: sheet)
        #expect(pasted.path.hasPrefix("assets/image-") && pasted.path.hasSuffix(".png"))
    }
}
