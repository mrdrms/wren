import CryptoKit
import Foundation
import Testing
@testable import writer

@MainActor
struct PublishingTests {
    @Test func preparesAPostForPlatforms() {
        let text = "---\ntitle: \"Hello\"\ntags: [swift, writing]\n---\n# Hello\n\nBody with ![a](https://x.y/a.png) and {>>a note<<}."
        let post = PreparedPost(text: text, fallbackTitle: "Fallback", folder: nil)
        #expect(post.title == "Hello")
        #expect(post.tags == ["swift", "writing"])
        #expect(!post.markdown.hasPrefix("# Hello"))   // the platform shows the title itself
        #expect(!post.markdown.contains("a note"))     // margin notes never leave Wren
        #expect(post.localMedia.isEmpty)               // remote images are left alone
    }

    @Test func ghostTokenIsAValidHS256JWT() throws {
        let key = "64fac5417c4493b5d0c5e:" + String(repeating: "ab", count: 32)
        let token = try Publisher.ghostToken(apiKey: key, now: Date(timeIntervalSince1970: 1_700_000_000))
        let parts = token.split(separator: ".").map(String.init)
        #expect(parts.count == 3)
        func decode(_ part: String) -> [String: Any] {
            var base64 = part.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
            while base64.count % 4 != 0 { base64 += "=" }
            return (try? JSONSerialization.jsonObject(with: Data(base64Encoded: base64)!)) as? [String: Any] ?? [:]
        }
        #expect(decode(parts[0])["kid"] as? String == "64fac5417c4493b5d0c5e")
        #expect(decode(parts[1])["aud"] as? String == "/admin/")
        #expect(decode(parts[1])["exp"] as? Int == 1_700_000_300)
        let expected = HMAC<SHA256>.authenticationCode(for: Data((parts[0] + "." + parts[1]).utf8),
                                                       using: SymmetricKey(data: Data(hex: String(repeating: "ab", count: 32))!))
        #expect(Data(expected).base64URL == parts[2])
        #expect(throws: (any Error).self) { try Publisher.ghostToken(apiKey: "not-a-key") }
    }

    @Test func lineEditsBecomeMarginNotes() {
        let answer = "Sure!\n```json\n[{\"original\": \"was walking slowly\", \"suggestion\": \"ambled\", \"reason\": \"one vivid verb\"}, {\"original\": \"not in text\", \"suggestion\": \"x\", \"reason\": \"y\"}]\n```"
        let edits = AIEditor.parseLineEdits(answer)
        #expect(edits.count == 2)
        let result = AIEditor.annotate("She was walking slowly home.", with: edits)
        #expect(result.placed == 1)
        #expect(result.text == "She was walking slowly {>>✎ ambled (one vivid verb)<<} home.")
        #expect(AIEditor.parseLineEdits("no json here").isEmpty)
    }
}

@MainActor
struct FootnoteAndEbookTests {
    @Test func footnotesAreNumberedInOrderOfUse() {
        let html = MarkdownHTML.convert("First[^b] and second[^a].\n\n[^a]: Note A.\n[^b]: Note *B*.")
        #expect(html.contains("First<sup class=\"fnref\" id=\"fnref-1\"><a href=\"#fn-1\">1</a></sup>"))
        #expect(html.contains("second<sup class=\"fnref\" id=\"fnref-2\"><a href=\"#fn-2\">2</a></sup>"))
        #expect(html.contains("<li id=\"fn-1\"><p>Note <em>B</em>."))
        #expect(!html.contains("[^a]:"))
        // A note that's never referenced, or a reference with no note, is left as written.
        #expect(MarkdownHTML.convert("Lonely[^x].").contains("[^x]"))
    }

    @Test func printedChaptersCollectTheirNotes() {
        let (text, _) = BookTypography(fontSize: 11, openingDrop: 0).attributed("# One\n\nA claim[^1].\n\n[^1]: The source.")
        #expect(text.string.contains("A claim1."))
        #expect(text.string.contains("Notes"))
        #expect(text.string.contains("1.\tThe source."))
    }

    @Test func buildsAValidEpub() throws {
        let data = EPUBBuilder.build(title: "The Lighthouse & the Sea", author: "Ada", chapters: [
            "# Chapter 1\n\nIt began[^1] at sea.\n\n---\n\n- [x] done\n- [ ] not yet\n\n[^1]: Long ago.",
            "# Chapter 2\n\nA line<br> with *style* and a ![pic](https://x.y/p.png).",
        ], titlePage: true, folder: FileManager.default.temporaryDirectory)
        // Readers recognise an EPUB by an uncompressed "mimetype" entry at the very start.
        #expect(data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
        #expect(String(data: data.subdata(in: 30..<38), encoding: .utf8) == "mimetype")
        #expect(String(data: data.subdata(in: 38..<58), encoding: .utf8) == "application/epub+zip")
        #expect(EPUBBuilder.xhtml("<hr>\n<img src=\"a.png\" alt=\"\">") == "<hr/>\n<img src=\"a.png\" alt=\"\"/>")
        let out = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wren-test.epub")
        try data.write(to: out)
    }

    @Test func crcMatchesTheStandard() {
        #expect(CRC32.checksum(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}

struct SafetyTests {
    @Test func onlyWebAndMailLinksSurvive() {
        #expect(Safety.safeHref("https://a.b/c?d=1&amp;e=2") == "https://a.b/c?d=1&amp;e=2")
        #expect(Safety.safeHref("mailto:me@x.y") == "mailto:me@x.y")
        #expect(Safety.safeHref("#fn-1") == "#fn-1")
        #expect(Safety.safeHref("chapter-2.html") == "chapter-2.html")
        #expect(Safety.safeHref("notes/a:b.md") == "notes/a:b.md")
        #expect(Safety.safeHref("javascript:alert(1)") == "#")
        #expect(Safety.safeHref("JavaScript:alert(1)") == "#")
        #expect(Safety.safeHref("file:///etc/passwd") == "#")
        #expect(Safety.safeHref("x-apple.systempreferences:com.apple") == "#")
        #expect(!MarkdownHTML.convert("[click](javascript:alert(1))").contains("javascript"))
        #expect(!Safety.isSafeLink(URL(string: "file:///Applications/Calculator.app")!))
    }

    @Test func onlyMediaFilesAreIncluded() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wren-safety-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try "secret".write(to: folder.appendingPathComponent("keys.txt"), atomically: true, encoding: .utf8)
        try Data([1]).write(to: folder.appendingPathComponent("photo.png"))
        let post = PreparedPost(text: "![a](photo.png) ![b](keys.txt) ![c](\(folder.path)/keys.txt)", fallbackTitle: "T", folder: folder)
        #expect(post.localMedia.map(\.path) == ["photo.png"])
        let html = Exporter.embedMedia(in: "<img src=\"keys.txt\"><img src=\"photo.png\">", folder: folder)
        #expect(html.contains("src=\"keys.txt\""))      // not embedded
        #expect(html.contains("data:image/png;base64")) // the real image is
    }

    @Test func adminAddressesAreTrimmedToTheSite() {
        #expect(PublishAccount(platform: .ghost, site: "https://me.ghost.io/ghost/").baseURL == "https://me.ghost.io")
        #expect(PublishAccount(platform: .wordpress, site: "blog.example.com/wp-admin/").baseURL == "https://blog.example.com")
    }
}
