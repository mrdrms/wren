import Foundation

/// Markdown footnotes: `a claim[^1]` in the text, and `[^1]: the note.` on a line of its own.
/// Notes are numbered in the order they're first referenced, whatever their labels.
nonisolated enum Footnotes {
    static let definition = try! NSRegularExpression(pattern: #"^\[\^([^\]\s]+)\]:[ \t]*(.*)$"#, options: .anchorsMatchLines)
    static let reference = try! NSRegularExpression(pattern: #"\[\^([^\]\s]+)\](?!:)"#)

    /// The text without its note lines, and the notes by label.
    static func extract(_ text: String) -> (body: String, notes: [String: String]) {
        let ns = text as NSString
        var notes: [String: String] = [:]
        let matches = definition.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return (text, [:]) }
        let body = NSMutableString(string: text)
        for match in matches.reversed() {
            notes[ns.substring(with: match.range(at: 1))] = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
            // Take the line break with it, so no blank gap is left behind.
            var line = match.range
            if NSMaxRange(line) < body.length { line.length += 1 }
            body.replaceCharacters(in: line, with: "")
        }
        return (body as String, notes)
    }

    /// Labels in the order they're first referenced, keeping only those with a note.
    static func order(in text: String, notes: [String: String]) -> [String] {
        var seen: [String] = []
        let ns = text as NSString
        for match in reference.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let label = ns.substring(with: match.range(at: 1))
            if notes[label] != nil, !seen.contains(label) { seen.append(label) }
        }
        return seen
    }

    /// Footnoted HTML: references become numbered superscript links, notes a list at the end.
    static func html(_ html: String, notes: [String: String], prefix: String = "", inline: (String) -> String) -> String {
        let order = order(in: html, notes: notes)
        guard !order.isEmpty else { return html }
        let result = NSMutableString(string: html)
        for match in reference.matches(in: html, range: NSRange(location: 0, length: result.length)).reversed() {
            let label = result.substring(with: match.range(at: 1))
            guard let index = order.firstIndex(of: label) else { continue }
            let n = index + 1
            result.replaceCharacters(in: match.range, with: "<sup class=\"fnref\" id=\"\(prefix)fnref-\(n)\"><a href=\"#\(prefix)fn-\(n)\">\(n)</a></sup>")
        }
        let items = order.enumerated().map { index, label in
            "<li id=\"\(prefix)fn-\(index + 1)\"><p>\(inline(notes[label] ?? "")) <a href=\"#\(prefix)fnref-\(index + 1)\">↩</a></p></li>"
        }
        return (result as String) + "\n<section class=\"footnotes\"><ol>\n" + items.joined(separator: "\n") + "\n</ol></section>"
    }
}
