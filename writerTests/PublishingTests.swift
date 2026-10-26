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
