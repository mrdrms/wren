import Foundation

struct StorySection: Identifiable, Equatable {
    let id: Int
    let title: String
    let text: String
    let words: Int
    let synopsis: String
}

/// Splits a sheet into sections at its headings so they can be rearranged as cards,
/// then stitches the Markdown back together.
enum Storyboard {
    struct Board: Equatable {
        let preamble: String
        let sections: [StorySection]
    }

    static func split(_ text: String) -> Board {
        let headings = Heading.parse(text)
        guard let minLevel = headings.map(\.level).min() else { return Board(preamble: text, sections: []) }
        // A lone top-level title stays put; split on the level below it instead.
        var level = minLevel
        var title: Heading?
        if headings.filter({ $0.level == minLevel }).count == 1, let deeper = headings.map(\.level).filter({ $0 > minLevel }).min() {
            level = deeper
            title = headings.first { $0.level == minLevel }
        }
        let starts = headings.filter { $0.level <= level && $0 != title }.map(\.range.location)
        guard let first = starts.first else { return Board(preamble: text, sections: []) }

        let ns = text as NSString
        let bounds = starts + [ns.length]
        let sections = starts.indices.map { i -> StorySection in
            let chunk = ns.substring(with: NSRange(location: bounds[i], length: bounds[i + 1] - bounds[i]))
            let lines = chunk.split(separator: "\n", omittingEmptySubsequences: true)
            let heading = lines.first.map { $0.drop { $0 == "#" }.trimmingCharacters(in: .whitespaces) } ?? ""
            let body = Ghost.clean(lines.dropFirst().filter { !$0.hasPrefix("#") }.joined(separator: " "))
            return StorySection(id: i, title: heading, text: chunk, words: TextStats.contentWords(body),
                                synopsis: String(LibraryStore.titleAndPreview(text: "x\n" + body, fallback: "").1.prefix(220)))
        }
        return Board(preamble: ns.substring(to: first), sections: sections)
    }

    static func join(_ board: Board) -> String {
        var result = board.preamble
        for (index, section) in board.sections.enumerated() {
            var chunk = section.text
            let isLast = index == board.sections.count - 1
            if !isLast {
                // The old last section may lack a trailing newline; give it a paragraph break.
                if !chunk.hasSuffix("\n") { chunk += "\n\n" } else if !chunk.hasSuffix("\n\n") { chunk += "\n" }
            }
            result += chunk
        }
        return result
    }

    /// Moves the section at `from` so it sits before the one currently at `to`.
    static func move(_ text: String, from: Int, to: Int) -> String {
        let board = split(text)
        guard board.sections.indices.contains(from), board.sections.indices.contains(to), from != to else { return text }
        var sections = board.sections
        let moved = sections.remove(at: from)
        sections.insert(moved, at: to)
        return join(Board(preamble: board.preamble, sections: sections))
    }
}
