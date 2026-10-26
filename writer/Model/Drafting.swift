import Foundation

/// Flow Lock: instead of deleting, finished words are struck through as CriticMarkup
/// deletions (`{--like this--}`), so you keep moving forward and decide later.
/// The file stays plain text that other CriticMarkup-aware tools understand.
enum Ghost {
    static let open = "{--"
    static let close = "--}"

    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
        let caret: Int
    }

    private static let ghostRegex = try! NSRegularExpression(pattern: "\\{--[\\s\\S]*?--\\}")
    private static let sweepRegex = try! NSRegularExpression(pattern: "[ \\t]*(?:\\{--[\\s\\S]*?--\\}[ \\t]*)+")
    private static let commentRegex = try! NSRegularExpression(pattern: "[ \\t]?\\{>>[\\s\\S]*?<<\\}")

    private static func isSpace(_ c: unichar) -> Bool { c == 32 || c == 9 }
    private static func isWhitespace(_ c: unichar) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }

    /// What Backspace does under Flow Lock. `nil` means "delete normally": you can always fix
    /// typos inside the word you're typing, but finished words get struck instead of erased.
    static func backspace(_ ns: NSString, caret: Int) -> Edit? {
        guard caret > 0, caret <= ns.length else { return nil }
        let before = ns.character(at: caret - 1)
        if before == 10 { return nil }
        let afterGhost = caret >= 3 && ns.substring(with: NSRange(location: caret - 3, length: 3)) == close
        if !isSpace(before) && !afterGhost { return nil }

        var end = caret
        while end > 0 && isSpace(ns.character(at: end - 1)) { end -= 1 }
        guard end > 0, ns.character(at: end - 1) != 10 else { return nil }

        if end >= 3, ns.substring(with: NSRange(location: end - 3, length: 3)) == close {
            // Grow the ghost we're sitting after by one more word.
            let start = ns.range(of: open, options: .backwards, range: NSRange(location: 0, length: end - 3)).location
            guard start != NSNotFound else { return nil }
            var wordEnd = start
            while wordEnd > 0 && isSpace(ns.character(at: wordEnd - 1)) { wordEnd -= 1 }
            guard wordEnd > 0, !isWhitespace(ns.character(at: wordEnd - 1)) else {
                return Edit(range: NSRange(location: caret, length: 0), replacement: "", caret: caret)
            }
            var wordStart = wordEnd
            while wordStart > 0 && !isWhitespace(ns.character(at: wordStart - 1)) { wordStart -= 1 }
            let word = ns.substring(with: NSRange(location: wordStart, length: start - wordStart))
            let inner = ns.substring(with: NSRange(location: start + 3, length: end - 3 - (start + 3)))
            return Edit(range: NSRange(location: wordStart, length: end - wordStart),
                        replacement: open + word + inner + close, caret: caret)
        }

        var start = end
        while start > 0 && !isWhitespace(ns.character(at: start - 1)) { start -= 1 }
        let word = ns.substring(with: NSRange(location: start, length: end - start))
        return Edit(range: NSRange(location: start, length: end - start), replacement: open + word + close, caret: caret + 6)
    }

    /// Strikes a selection (or the partial word before the caret, for ⌥⌫).
    static func strike(_ ns: NSString, range: NSRange) -> Edit? {
        guard range.length > 0 else { return nil }
        let text = ns.substring(with: range)
        guard !text.allSatisfy(\.isWhitespace) else { return nil }
        return Edit(range: range, replacement: open + text + close, caret: NSMaxRange(range) + 6)
    }

    static func wordBackward(_ ns: NSString, caret: Int) -> Edit? {
        var start = caret
        while start > 0 && !isWhitespace(ns.character(at: start - 1)) { start -= 1 }
        if start == caret { return backspace(ns, caret: caret) }
        return strike(ns, range: NSRange(location: start, length: caret - start))
    }

    static func count(_ text: String) -> Int {
        guard text.contains(open) else { return 0 }
        return ghostRegex.numberOfMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    /// Accept all strikes: remove them and tidy the spacing they leave behind.
    static func sweep(_ text: String) -> String {
        guard text.contains(open) else { return text }
        let result = NSMutableString(string: text)
        let matches = sweepRegex.matches(in: text, range: NSRange(location: 0, length: result.length))
        for m in matches.reversed() {
            let before: unichar = m.range.location == 0 ? 10 : result.character(at: m.range.location - 1)
            let afterIndex = NSMaxRange(m.range)
            let after: unichar = afterIndex >= result.length ? 10 : result.character(at: afterIndex)
            let punctuation = ".,;:!?)]\"'".utf16
            let joinWithSpace = before != 10 && after != 10 && !punctuation.contains(after)
            result.replaceCharacters(in: m.range, with: joinWithSpace ? " " : "")
        }
        return result as String
    }

    /// Reject all strikes: bring the words back.
    static func restore(_ text: String) -> String {
        guard text.contains(open) else { return text }
        return ghostRegex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length)) { m, ns in
            let inner = NSRange(location: m.range.location + 3, length: m.range.length - 6)
            return ns.substring(with: inner)
        }
    }

    /// The text as a reader would see it: strikes swept, margin notes removed.
    static func clean(_ text: String) -> String {
        var result = sweep(text)
        if result.contains("{>>") {
            result = commentRegex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: (result as NSString).length), withTemplate: "")
        }
        return result
    }
}

/// Margin notes (`{>>like this<<}`) and TK placeholders: things to come back to.
struct DraftNote: Identifiable, Equatable {
    enum Kind { case note, tk }
    var id: Int { range.location }
    let kind: Kind
    let text: String
    let range: NSRange

    private static let noteRegex = try! NSRegularExpression(pattern: "\\{>>([\\s\\S]*?)<<\\}")
    private static let tkRegex = try! NSRegularExpression(pattern: "\\bTK\\b")

    static func parse(_ text: String) -> [DraftNote] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var notes: [DraftNote] = []
        if text.contains("{>>") {
            for m in noteRegex.matches(in: text, range: full) {
                notes.append(DraftNote(kind: .note, text: ns.substring(with: m.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines), range: m.range))
            }
        }
        if text.contains("TK") {
            for m in tkRegex.matches(in: text, range: full) {
                let line = ns.substring(with: ns.lineRange(for: m.range)).trimmingCharacters(in: .whitespacesAndNewlines)
                notes.append(DraftNote(kind: .tk, text: String(line.prefix(80)), range: m.range))
            }
        }
        return notes.sorted { $0.range.location < $1.range.location }
    }
}

private extension NSRegularExpression {
    func stringByReplacingMatches(in string: String, range: NSRange, using transform: (NSTextCheckingResult, NSString) -> String) -> String {
        let ns = string as NSString
        let result = NSMutableString(string: string)
        for m in matches(in: string, range: range).reversed() {
            result.replaceCharacters(in: m.range, with: transform(m, ns))
        }
        return result as String
    }
}
