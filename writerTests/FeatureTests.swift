import Foundation
import Testing
@testable import writer

struct FlowLockTests {
    private func run(_ text: String, caret: Int? = nil) -> (String, Int)? {
        let ns = NSMutableString(string: text)
        let caret = caret ?? ns.length
        guard let edit = Ghost.backspace(ns, caret: caret) else { return nil }
        ns.replaceCharacters(in: edit.range, with: edit.replacement)
        return (ns as String, edit.caret)
    }

    @Test func typosInsideTheCurrentWordDeleteNormally() {
        #expect(run("I walked slowl") == nil)
    }

    @Test func backspaceAfterAWordStrikesIt() {
        let (text, caret) = run("I walked slowly ")!
        #expect(text == "I walked {--slowly--} ")
        #expect(caret == (text as NSString).length)
    }

    @Test func repeatedBackspaceGrowsTheStrike() {
        var (text, caret) = run("I walked slowly ")!
        (text, caret) = run(text, caret: caret)!
        #expect(text == "I {--walked slowly--} ")
        #expect(caret == (text as NSString).length)
    }

    @Test func neverCrossesIntoThePreviousParagraph() {
        #expect(run("First line\n") == nil)
        #expect(run("") == nil)
    }

    @Test func sweepRemovesStrikesAndTidiesSpacing() {
        #expect(Ghost.sweep("I {--walked--} ran home.") == "I ran home.")
        #expect(Ghost.sweep("I ran {--slowly--}.") == "I ran.")
        #expect(Ghost.sweep("{--Gone.--} Kept") == "Kept")
        #expect(Ghost.count("a {--b--} c {--d--}") == 2)
    }

    @Test func restoreAndCleanForExport() {
        #expect(Ghost.restore("I {--walked slowly--} ran") == "I walked slowly ran")
        #expect(Ghost.clean("Fact TK{>>check this<<} here {--old--}") == "Fact TK here")
    }

    @Test func notesAndTKsAreFound() {
        let notes = DraftNote.parse("Born in TK. {>> verify <<}")
        #expect(notes.map(\.kind) == [.tk, .note])
        #expect(notes.last?.text == "verify")
    }
}

struct HistoryTests {
    @Test func diffAppliesAndReverts() {
        let a = "The quick fox", b = "The quick brown fox"
        let change = TextChange.between(a, b)!
        #expect(change.old.isEmpty && change.new == "brown ")
        let s = NSMutableString(string: a)
        change.apply(to: s)
        #expect(s as String == b)
        change.revert(on: s)
        #expect(s as String == a)
        #expect(TextChange.between(a, a) == nil)
    }

    @Test func diffNeverSplitsEmoji() {
        let change = TextChange.between("a😀b", "a😃b")!
        let s = NSMutableString(string: "a😀b")
        change.apply(to: s)
        #expect(s as String == "a😃b")
    }

    @Test func replayRebuildsTheLatestText() {
        let steps = ["", "Hello", "Hello world", "Hi world", "Hi world!"]
        let changes = zip(steps, steps.dropFirst()).compactMap { TextChange.between($0, $1) }
        #expect(HistoryStore.replay(changes) == "Hi world!")
        let player = TimeMachinePlayer(changes: changes)
        player.seek(to: 2)
        #expect(player.text == "Hello world")
        player.seek(to: 0)
        #expect(player.text == "")
        player.seek(to: 4)
        #expect(player.text == "Hi world!")
    }
}

struct StoryboardTests {
    let text = "# Book\nIntro.\n\n## One\nFirst.\n\n## Two\nSecond.\n\n## Three\nThird."

    @Test func splitsBelowALoneTitle() {
        let board = Storyboard.split(text)
        #expect(board.preamble == "# Book\nIntro.\n\n")
        #expect(board.sections.map(\.title) == ["One", "Two", "Three"])
        #expect(Storyboard.join(board) == text)
    }

    @Test func movingSectionsKeepsEveryWord() {
        let moved = Storyboard.move(text, from: 2, to: 0)
        #expect(moved == "# Book\nIntro.\n\n## Three\nThird.\n\n## One\nFirst.\n\n## Two\nSecond.\n\n")
        #expect(TextStats.wordCount(moved) == TextStats.wordCount(text))
    }
}

struct LensAndVoiceTests {
    @Test func echoesFlagNearbyRepeatsOnly() {
        let echoes = StyleLens.echoes(in: "The garden was quiet. Later the garden bloomed.", range: NSRange(location: 0, length: 47))
        #expect(echoes.count == 2)
        #expect(StyleLens.echoes(in: "The garden was quiet.", range: NSRange(location: 0, length: 21)).isEmpty)
    }

    @Test func rhythmVarietyRewardsMixedLengths() {
        #expect(Rhythm.variety([10, 10, 11, 10, 10])! < 35)
        #expect(Rhythm.variety([2, 25, 6, 30, 4])! > 60)
        #expect(Rhythm.sentenceLengths("# Title\n\nOne two three. Four five.") == [3, 2])
    }

    @Test func speakableTextKeepsOffsets() {
        let source = "## Hi **there** {--gone--} [link](http://x)"
        let spoken = ReadAloud.speakable(source)
        #expect((spoken as NSString).length == (source as NSString).length)
        #expect(!spoken.contains("gone") && !spoken.contains("http") && !spoken.contains("*"))
        #expect(spoken.contains("there") && spoken.contains("link"))
    }
}

struct StoryboardPreviewTests {
    @Test func synopsisHidesDraftingMarks() {
        let board = Storyboard.split("## A\nKeep {--cut--} this{>>note<<}.\n\n## B\nMore.")
        #expect(board.sections.first?.synopsis == "Keep this.")
        #expect(board.sections.first?.words == 2)
    }
}
