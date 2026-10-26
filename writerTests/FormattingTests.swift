import AppKit
import Foundation
import Testing
@testable import writer

@MainActor
struct FormattingTests {
    private func editor(_ text: String, selection: NSRange) -> WrenTextView {
        let view = WrenTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        view.string = text
        view.setSelectedRange(selection)
        return view
    }

    @Test func blockStylesApplyToEverySelectedLine() {
        let view = editor("one\ntwo\n\nthree", selection: NSRange(location: 0, length: 14))
        view.apply(.numbered)
        #expect(view.string == "1. one\n2. two\n\n3. three")
        view.apply(.numbered) // same style again turns it off
        #expect(view.string == "one\ntwo\n\nthree")
        view.setSelectedRange(NSRange(location: 0, length: 0))
        view.apply(.heading(2))
        #expect(view.string.hasPrefix("## one\n"))
        view.apply(.bullet) // switching styles replaces the prefix
        #expect(view.string.hasPrefix("- one\n"))
        view.apply(.paragraph)
        #expect(view.string.hasPrefix("one\n"))
    }

    @Test func boldWrapsTheWordAndTogglesOff() {
        let view = editor("make this bold", selection: NSRange(location: 6, length: 0)) // caret inside "this"
        view.apply(.bold)
        #expect(view.string == "make **this** bold")
        view.setSelectedRange(NSRange(location: 8, length: 2)) // inside the bold word
        view.apply(.bold)
        #expect(view.string == "make this bold")
    }

    @Test func markersHugWordsNotSpaces() {
        let view = editor("a word here", selection: NSRange(location: 1, length: 6)) // " word "
        view.apply(.italic)
        #expect(view.string == "a *word* here")
    }

    @Test func checkboxesToggleThroughReplace() {
        let view = editor("- [ ] buy milk", selection: NSRange(location: 0, length: 0))
        view.replace(NSRange(location: 2, length: 3), with: "[x]")
        #expect(view.string == "- [x] buy milk")
        #expect(BlockKind.of(line: view.string) == .task)
    }

    @Test func detectsBlockKinds() {
        #expect(BlockKind.of(line: "# Title") == .title)
        #expect(BlockKind.of(line: "## Section") == .heading)
        #expect(BlockKind.of(line: "#### Deep") == .subheading)
        #expect(BlockKind.of(line: "  - item") == .bullet)
        #expect(BlockKind.of(line: "12. step") == .numbered)
        #expect(BlockKind.of(line: "> quoted") == .quote)
        #expect(BlockKind.of(line: "#hashtag") == .body)
    }

    @Test func slashMenuFindsItemsByNameOrKeyword() {
        #expect(SlashCatalog.filter("").count == SlashCatalog.all.count)
        #expect(SlashCatalog.filter("head").first?.id == "h2")
        #expect(SlashCatalog.filter("photo").first?.id == "image")
        #expect(SlashCatalog.filter("todo").first?.id == "task")
        #expect(SlashCatalog.filter("zzz").isEmpty)
    }

    @Test func richTextBecomesMarkdown() {
        let body = NSFont.systemFont(ofSize: 12)
        let text = NSMutableAttributedString()
        text.append(NSAttributedString(string: "Big Title\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 24)]))
        text.append(NSAttributedString(string: "Some ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "bold ", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)]))
        text.append(NSAttributedString(string: "and a ", attributes: [.font: body]))
        text.append(NSAttributedString(string: "link", attributes: [.font: body, .link: URL(string: "https://wren.app")!]))
        text.append(NSAttributedString(string: ".\n", attributes: [.font: body]))
        let list = NSTextList(markerFormat: .disc, options: 0)
        let style = NSMutableParagraphStyle()
        style.textLists = [list]
        text.append(NSAttributedString(string: "\t•\tfirst\n", attributes: [.font: body, .paragraphStyle: style]))
        text.append(NSAttributedString(string: "\t•\tsecond", attributes: [.font: body, .paragraphStyle: style]))

        #expect(RichPaste.markdown(from: text) == "# Big Title\n\nSome **bold** and a [link](https://wren.app).\n\n- first\n- second")
    }

    @Test func codeFromEditorsStaysVerbatim() {
        let mono = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let code = NSAttributedString(string: "let x = **y**", attributes: [.font: mono])
        #expect(RichPaste.markdown(from: code) == "let x = **y**")
    }
}
