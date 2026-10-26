import Foundation
import Testing
@testable import writer

struct TextStatsTests {
    @Test func countsWordsIgnoringMarkdownSymbols() {
        #expect(TextStats.wordCount("# Hello world\n\n- one\n- two\n> quoted *text*") == 6)
        #expect(TextStats.wordCount("   ") == 0)
        #expect(TextStats.wordCount("It's 2026 — finally!") == 3)
    }

    @Test func countsSentencesAndParagraphs() {
        let stats = TextStats.compute("One sentence. Two sentences! Three?\n\nNew paragraph here")
        #expect(stats.sentences == 4)
        #expect(stats.paragraphs == 2)
        #expect(stats.words == 8)
    }

    @Test func readingEaseNeedsEnoughText() {
        #expect(TextStats.compute("Too short.").readingEase == nil)
        let simple = Array(repeating: "The cat sat on the mat.", count: 10).joined(separator: " ")
        #expect((TextStats.compute(simple).readingEase ?? 0) > 80)
    }

    @Test func parsesHeadingsOutsideCodeFences() {
        let headings = Heading.parse("# Title\ntext\n```\n# not a heading\n```\n## Section\n#nospace")
        #expect(headings.map(\.title) == ["Title", "Section"])
        #expect(headings.map(\.level) == [1, 2])
    }
}

struct StyleLensTests {
    @Test func flagsEachKind() {
        let matches = StyleLens.analyze("He ran quickly. It was really the the end. The letter was written by her.")
        let kinds = Set(matches.map(\.kind))
        #expect(kinds == [.adverb, .filler, .repeated, .passive])
    }

    @Test func ignoresCommonNonAdverbs() {
        #expect(StyleLens.analyze("Only my family will reply early.").isEmpty)
    }
}

struct MarkdownHTMLTests {
    @Test func convertsBlocks() {
        let html = MarkdownHTML.convert("# Title\n\nHello **bold** and *it*.\n\n- a\n- b\n\n1. x\n\n> quote\n\n---")
        #expect(html.contains("<h1>Title</h1>"))
        #expect(html.contains("<p>Hello <strong>bold</strong> and <em>it</em>.</p>"))
        #expect(html.contains("<ul>\n  <li>a</li>\n  <li>b</li>\n</ul>"))
        #expect(html.contains("<ol>\n  <li>x</li>\n</ol>"))
        #expect(html.contains("<blockquote><p>quote</p></blockquote>"))
        #expect(html.contains("<hr>"))
    }

    @Test func leavesCodeUntouchedAndEscapesHTML() {
        #expect(MarkdownHTML.inline("use `**x** <b>` here") == "use <code>**x** &lt;b&gt;</code> here")
        let fenced = MarkdownHTML.convert("```\n# not heading\n<tag>\n```")
        #expect(fenced == "<pre><code># not heading\n&lt;tag&gt;</code></pre>")
    }

    @Test func convertsLinksTasksAndHighlights() {
        #expect(MarkdownHTML.inline("[Wren](https://x.y) ==hi== ~~no~~") == "<a href=\"https://x.y\">Wren</a> <mark>hi</mark> <del>no</del>")
        #expect(MarkdownHTML.convert("- [x] done").contains("<input type=\"checkbox\" disabled checked> done"))
    }
}

struct LibraryTests {
    @Test func derivesTitleAndPreview() {
        let (title, preview) = LibraryStore.titleAndPreview(text: "\n# My **Story**\n\nOnce upon a time.\n", fallback: "file")
        #expect(title == "My Story")
        #expect(preview == "Once upon a time.")
        #expect(LibraryStore.titleAndPreview(text: "", fallback: "Untitled").0 == "Untitled")
    }

    @Test func sanitizesFileNames() {
        #expect(LibraryStore.sanitize("a/b:c?") == "a b c")
        #expect(LibraryStore.sanitize("  .hidden ") == "hidden")
    }

    @Test func fuzzyScoringPrefersWordStarts() {
        #expect(CommandPalette.fuzzyScore("zm", "Zen Mode") != nil)
        #expect(CommandPalette.fuzzyScore("xyz", "Zen Mode") == nil)
        #expect(CommandPalette.fuzzyScore("ty", "Typewriter")! > CommandPalette.fuzzyScore("ty", "Style Lens: Off") ?? 0)
    }
}

struct StyleLensLineTests {
    @Test func repeatedWordsMustShareALine() {
        #expect(StyleLens.analyze("# Wren\n\nWren is here").isEmpty)
    }
}
