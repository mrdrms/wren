import AppKit
import Foundation

/// The words a reader actually sees: Markdown symbols, link addresses, images, front matter,
/// struck text and margin notes removed. Every count in Wren is based on this.
enum MarkdownText {
    private static func rule(_ pattern: String, _ template: String) -> (NSRegularExpression, String) {
        (try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]), template)
    }

    private static let rules: [(NSRegularExpression, String)] = [
        rule("^[ \\t]*```.*$", ""),                                        // code fence lines (the code inside counts)
        rule("^[ \\t]*([-*_])([ \\t]*\\1){2,}[ \\t]*$", ""),                // dividers
        rule("!\\[[^\\]\\n]*\\]\\([^)\\n]*\\)", ""),                       // images and videos
        rule("\\[([^\\]\\n]+)\\]\\([^)\\n]*\\)", "$1"),                   // links: keep the text, drop the address
        rule("<((?:https?|mailto):[^>\\s]+)>", "$1"),                       // autolinks
        rule("^[ \\t]{0,3}#{1,6}[ \\t]+", ""),                              // heading marks
        rule("^[ \\t]*(?:>[ \\t]?)+", ""),                                  // quote marks
        rule("^[ \\t]*(?:[-*+]|\\d+[.)])[ \\t]+(?:\\[[ xX]\\][ \\t]+)?", ""),    // list bullets, numbers and checkboxes
        rule("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1", "$2"),                      // bold
        rule("(?<![\\*\\w])\\*(?![\\*\\s])(.+?)(?<![\\*\\s])\\*(?![\\*\\w])", "$1"), // italic *
        rule("(?<![_\\w])_(?![_\\s])(.+?)(?<![_\\s])_(?![_\\w])", "$1"),         // italic _
        rule("~~(?=\\S)(.+?)(?<=\\S)~~", "$1"),                               // strikethrough
        rule("==(?=\\S)(.+?)(?<=\\S)==", "$1"),                               // highlight
        rule("`([^`\\n]+)`", "$1"),                                         // inline code
    ]

    static func plain(_ markdown: String) -> String {
        var text = FrontMatter.strip(markdown)
        if text.contains("{") { text = Ghost.clean(text) }
        for (regex, template) in rules {
            text = regex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: template)
        }
        return text
    }
}

struct TextStats: Equatable {
    var words = 0
    /// Letters, digits, punctuation and spaces; line breaks don't count.
    var characters = 0
    var charactersNoSpaces = 0
    var sentences = 0
    var paragraphs = 0
    var syllables = 0

    /// Seconds to read at an average adult silent-reading pace.
    var readingTime: TimeInterval { Double(words) / 238 * 60 }
    /// Seconds to read aloud.
    var speakingTime: TimeInterval { Double(words) / 130 * 60 }
    var averageSentenceLength: Double { sentences == 0 ? 0 : Double(words) / Double(sentences) }

    /// Flesch reading ease (0–100, higher is easier). Needs enough text to be meaningful.
    var readingEase: Double? {
        guard words >= 30, sentences > 0 else { return nil }
        let score = 206.835 - 1.015 * (Double(words) / Double(sentences)) - 84.6 * (Double(syllables) / Double(words))
        return min(100, max(0, score))
    }

    var readingEaseLabel: String {
        guard let ease = readingEase else { return "Keep writing…" }
        switch ease {
        case 80...: return "Breezy"
        case 65..<80: return "Plain English"
        case 50..<65: return "Fairly difficult"
        case 30..<50: return "Difficult"
        default: return "Very dense"
        }
    }

    /// Statistics for a Markdown sheet, counting only what readers will see.
    static func forContent(_ markdown: String) -> TextStats {
        compute(MarkdownText.plain(markdown))
    }

    /// Words a reader sees in a Markdown sheet.
    static func contentWords(_ markdown: String) -> Int {
        wordCount(MarkdownText.plain(markdown))
    }

    static func compute(_ text: String) -> TextStats {
        var stats = TextStats()
        for ch in text where !ch.isNewline {
            stats.characters += 1
            if !ch.isWhitespace { stats.charactersNoSpaces += 1 }
        }
        for token in text.split(whereSeparator: { $0.isWhitespace }) where isWord(token) {
            stats.words += 1
            stats.syllables += syllableCount(token)
        }
        // A sentence is words followed by terminal punctuation and whitespace, or by the end of the text.
        var hasWords = false
        var sentenceEnded = false
        for ch in text {
            if ch == "." || ch == "!" || ch == "?" {
                sentenceEnded = hasWords
            } else if ch.isWhitespace {
                if sentenceEnded {
                    stats.sentences += 1
                    hasWords = false
                    sentenceEnded = false
                }
            } else if ch.isLetter || ch.isNumber {
                hasWords = true
                sentenceEnded = false
            }
        }
        if hasWords { stats.sentences += 1 }
        stats.paragraphs = text.split(separator: "\n").filter { !$0.allSatisfy(\.isWhitespace) }.count
        return stats
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).reduce(0) { $0 + (isWord($1) ? 1 : 0) }
    }

    private static func isWord(_ token: Substring) -> Bool {
        token.contains { $0.isLetter || $0.isNumber }
    }

    static func syllableCount(_ token: Substring) -> Int {
        let word = token.lowercased().filter(\.isLetter)
        guard !word.isEmpty else { return 0 }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]
        var count = 0
        var previousWasVowel = false
        for ch in word {
            let isVowel = vowels.contains(ch)
            if isVowel && !previousWasVowel { count += 1 }
            previousWasVowel = isVowel
        }
        if word.hasSuffix("e") && !word.hasSuffix("le") && count > 1 { count -= 1 }
        return max(count, 1)
    }
}

struct Heading: Identifiable, Equatable {
    let id: Int // character offset of the heading line
    let level: Int
    let title: String
    let range: NSRange

    static func parse(_ text: String) -> [Heading] {
        var result: [Heading] = []
        let ns = text as NSString
        var inFence = false
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            let line = ns.substring(with: range)
            if line.hasPrefix("```") { inFence.toggle(); return }
            guard !inFence, line.hasPrefix("#") else { return }
            let hashes = line.prefix { $0 == "#" }
            guard hashes.count <= 6, line.dropFirst(hashes.count).first == " " else { return }
            let title = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return }
            result.append(Heading(id: range.location, level: hashes.count, title: title, range: range))
        }
        return result
    }
}

/// Highlights habits that weaken prose: adverbs, filler words, passive voice, repeats and echoes.
enum StyleLens {
    enum Kind: String, CaseIterable, Identifiable {
        case adverb, filler, passive, repeated, echo
        var id: String { rawValue }
        var label: String {
            switch self {
            case .adverb: "Adverbs"
            case .filler: "Filler words"
            case .passive: "Passive voice"
            case .repeated: "Repeated words"
            case .echo: "Echoes"
            }
        }
        var hint: String {
            switch self {
            case .adverb: "Try a stronger verb instead."
            case .filler: "Often safe to cut."
            case .passive: "Who is doing the action?"
            case .repeated: "Probably a typo."
            case .echo: "Same word used again nearby."
            }
        }
        var color: NSColor {
            switch self {
            case .adverb: NSColor(hex: 0x4C8DFF)
            case .filler: NSColor(hex: 0xF5A524)
            case .passive: NSColor(hex: 0x16B88A)
            case .repeated: NSColor(hex: 0xF2545B)
            case .echo: NSColor(hex: 0xA66CFF)
            }
        }
    }

    struct Match: Equatable {
        let range: NSRange
        let kind: Kind
    }

    private static let notAdverbs: Set<String> = [
        "only", "family", "reply", "early", "apply", "supply", "holy", "daily", "july", "italy", "fly", "ugly",
        "belly", "rely", "ally", "bully", "jelly", "lovely", "lonely", "friendly", "likely", "silly", "hilly",
        "curly", "chilly", "jolly", "elderly", "costly", "deadly", "lively", "ugly", "monthly", "weekly",
        "yearly", "assembly", "anomaly", "butterfly", "dragonfly", "emily", "lily", "molly", "sally", "kelly",
    ]

    private static let adverbRegex = try! NSRegularExpression(pattern: "\\b[A-Za-z]{3,}ly\\b")
    private static let fillerRegex = try! NSRegularExpression(
        pattern: "\\b(very|really|just|quite|actually|basically|literally|somewhat|totally|simply|perhaps|rather|definitely|certainly|kind of|sort of|a lot|in order to|that being said|needless to say)\\b",
        options: .caseInsensitive)
    private static let passiveRegex = try! NSRegularExpression(
        pattern: "\\b(is|are|was|were|be|been|being|am)\\s+(\\w+ed|written|done|made|given|taken|seen|known|shown|told|found|built|held|kept|left|lost|paid|sold|sent|spent|thought|brought|caught|taught|bought|chosen|driven|eaten|forgotten|hidden|broken|spoken|stolen|frozen)\\b",
        options: .caseInsensitive)
    private static let repeatedRegex = try! NSRegularExpression(pattern: "\\b(\\w+)[ \\t]+\\1\\b", options: .caseInsensitive)

    private static let longWordRegex = try! NSRegularExpression(pattern: "\\b[\\p{L}']{5,}\\b")
    private static let echoStopWords: Set<String> = [
        "about", "which", "there", "their", "would", "could", "should", "these", "those", "where", "other", "being",
        "after", "before", "while", "because", "through", "might", "every", "still", "again", "first", "never",
    ]

    static func analyze(_ text: String) -> [Match] {
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var matches: [Match] = []
        for m in adverbRegex.matches(in: text, range: full) where !notAdverbs.contains(ns.substring(with: m.range).lowercased()) {
            matches.append(Match(range: m.range, kind: .adverb))
        }
        for m in fillerRegex.matches(in: text, range: full) {
            matches.append(Match(range: m.range, kind: .filler))
        }
        for m in passiveRegex.matches(in: text, range: full) {
            matches.append(Match(range: m.range, kind: .passive))
        }
        for m in repeatedRegex.matches(in: text, range: full) {
            // Only flag repeated words, not numbers like "10 10".
            if ns.substring(with: m.range(at: 1)).contains(where: \.isLetter) {
                matches.append(Match(range: m.range, kind: .repeated))
            }
        }
        matches += echoes(in: text, range: full)
        return matches
    }

    /// Distinctive words (5+ letters) that reappear within a few lines of each other.
    static func echoes(in text: String, range: NSRange, window: Int = 25) -> [Match] {
        let ns = text as NSString
        var lastSeen: [String: (index: Int, range: NSRange)] = [:]
        var flagged = Set<Int>()
        var result: [Match] = []
        for (index, m) in longWordRegex.matches(in: text, range: range).enumerated() {
            let word = ns.substring(with: m.range).lowercased()
            guard !echoStopWords.contains(word) else { continue }
            if let previous = lastSeen[word], index - previous.index <= window {
                if flagged.insert(previous.range.location).inserted { result.append(Match(range: previous.range, kind: .echo)) }
                if flagged.insert(m.range.location).inserted { result.append(Match(range: m.range, kind: .echo)) }
            }
            lastSeen[word] = (index, m.range)
        }
        return result
    }
}

/// Sentence lengths, for the Rhythm gutter and chart. Varied lengths read like music;
/// uniform lengths read like a drone.
enum Rhythm {
    enum Bucket: Int, CaseIterable {
        case short, medium, long, veryLong
        init(words: Int) {
            switch words {
            case ..<8: self = .short
            case ..<17: self = .medium
            case ..<28: self = .long
            default: self = .veryLong
            }
        }
        var label: String {
            switch self {
            case .short: "Short (1–7)"
            case .medium: "Medium (8–16)"
            case .long: "Long (17–27)"
            case .veryLong: "Very long (28+)"
            }
        }
        var color: NSColor {
            switch self {
            case .short: NSColor(hex: 0x2EB88A)
            case .medium: NSColor(hex: 0x4C8DFF)
            case .long: NSColor(hex: 0xE89A12)
            case .veryLong: NSColor(hex: 0xE5484D)
            }
        }
    }

    /// Word counts of each prose sentence, skipping headings and code.
    static func sentenceLengths(_ text: String) -> [Int] {
        let ns = text as NSString
        var lengths: [Int] = []
        var inFence = false
        ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byParagraphs]) { paragraph, range, _, _ in
            guard let paragraph else { return }
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { inFence.toggle(); return }
            guard !inFence, !trimmed.hasPrefix("#"), !trimmed.isEmpty else { return }
            ns.enumerateSubstrings(in: range, options: .bySentences) { sentence, _, _, _ in
                let words = TextStats.wordCount(sentence ?? "")
                if words > 0 { lengths.append(words) }
            }
        }
        return lengths
    }

    /// 0–100: how much sentence length varies (coefficient of variation, scaled).
    static func variety(_ lengths: [Int]) -> Int? {
        guard lengths.count >= 4 else { return nil }
        let mean = Double(lengths.reduce(0, +)) / Double(lengths.count)
        let variance = lengths.reduce(0) { $0 + pow(Double($1) - mean, 2) } / Double(lengths.count)
        return min(100, Int((variance.squareRoot() / mean) * 160))
    }
}
