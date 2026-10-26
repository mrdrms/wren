import Foundation
import Testing
@testable import writer

struct CountingTests {
    @Test func onlyWhatReadersSeeIsCounted() {
        let markdown = """
        ---
        title: "Front matter is not content"
        ---

        # My Title

        Some **bold** and *italic* words with a [link](https://example.com/a/very/long/path).

        - [x] done task
        1. first

        > quoted line

        ![A photo caption](assets/photo.png)

        ---

        Old {--deleted text--} new{>>private note<<} `code`.
        """
        let plain = MarkdownText.plain(markdown)
        #expect(!plain.contains("*") && !plain.contains("#") && !plain.contains("http") && !plain.contains("photo"))
        #expect(!plain.contains("[") && !plain.contains(">") && !plain.contains("Front matter"))
        #expect(!plain.contains("deleted") && !plain.contains("private note"))

        // My Title (2) + Some bold and italic words with a link (8) + done task (2) + first (1)
        // + quoted line (2) + Old new code (3)
        #expect(TextStats.contentWords(markdown) == 18)
    }

    @Test func charactersSkipMarkupAndLineBreaks() {
        let stats = TextStats.forContent("# Hi\n\n**Bold** [x](https://a.b)")
        // "Hi" + "Bold x": line breaks don't count, spaces do.
        #expect(stats.characters == 8)
        #expect(stats.charactersNoSpaces == 7)
        #expect(stats.words == 3)
    }

    @Test func codeInsideFencesStillCounts() {
        #expect(TextStats.contentWords("```swift\nlet answer = 42\n```") == 3)
    }

    @Test func plainProseIsUnchanged() {
        let prose = "Snake_case_names and 3 * 4 = 12 stay as they are."
        #expect(MarkdownText.plain(prose) == prose)
    }
}
