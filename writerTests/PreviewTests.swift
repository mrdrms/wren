import Foundation
import Testing
@testable import writer

struct PreviewTests {
    @Test func frontMatterBecomesPostHeader() {
        let body = BlogRenderer.body(markdown: "---\ntitle: \"Hello \\\"World\\\"\"\ndate: 2026-10-25\n---\n\nFirst paragraph.")
        #expect(body.hasPrefix("<header class=\"post-header\"><h1>Hello &quot;World&quot;</h1><p class=\"meta\">"))
        #expect(body.contains("1 min read"))
        #expect(body.contains("2026"))
        #expect(body.contains("<p>First paragraph.</p>"))
    }

    @Test func firstHeadingLeadsWithoutFrontMatter() {
        let body = BlogRenderer.body(markdown: "# Title\n\nText.")
        #expect(body.hasPrefix("<header class=\"post-header\"><h1>Title</h1><p class=\"meta\">1 min read</p></header>"))
        #expect(BlogRenderer.body(markdown: "Just text.") == "<p>Just text.</p>")
    }

    @Test func frontMatterFields() {
        let fields = FrontMatter.fields("---\ntitle: 'Quoted'\nTags: a, b\nurl: https://x.y/z\n---\nbody")
        #expect(fields["title"] == "Quoted")
        #expect(fields["tags"] == "a, b")
        #expect(fields["url"] == "https://x.y/z")
    }

    @Test func everyStyleHasLightAndDarkCSS() {
        for style in BlogStyle.allCases {
            #expect(style.css().contains("prefers-color-scheme: dark"))
            #expect(!style.css(print: true).contains("prefers-color-scheme"))
        }
        #expect(MarkdownHTML.document(title: "T", body: "<p>x</p>", style: .modern).contains("id=\"wren-content\""))
    }

    @Test func previewServesLocalMediaThroughItsScheme() {
        let html = BlogPreview.Coordinator.rewriteAssets("<img src=\"assets/a.png\" alt=\"\"><img src=\"https://x.y/b.png\"><video controls src=\"clip.mp4\">")
        #expect(html.contains("src=\"wren-asset://local/assets/a.png\""))
        #expect(html.contains("src=\"https://x.y/b.png\""))
        #expect(html.contains("src=\"wren-asset://local/clip.mp4\""))
    }
}
