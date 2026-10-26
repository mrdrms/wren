import AppKit

extension NSAttributedString.Key {
    /// Marks a list dash that should be drawn as a round bullet.
    static let wrenBullet = NSAttributedString.Key("WrenBullet")
}

/// Styles Markdown in place: the text stays plain, the page looks finished.
/// Markup characters are softened, or hidden entirely except in the paragraph you're
/// editing, so people who've never heard of Markdown just see formatted text.
final class MarkdownHighlighter {
    var theme = Theme.named("paper")
    var fontChoice = EditorFontChoice.serif
    var fontSize: CGFloat = 18
    var lineHeight: CGFloat = 1.6
    /// Preview size for an image path, so its line can reserve room beneath it.
    var imageSize: ((String) -> NSSize?)?
    /// Show Markdown as typed, with no rendering (the preview shows the result).
    var plain = true
    /// Hide markup characters outside `revealRange` (live formatting only).
    var hideMarkup = false
    /// The paragraph(s) being edited, where markup stays visible.
    var revealRange: NSRange?

    private static let hiddenFont = NSFont.systemFont(ofSize: 0.01)

    private static func regex(_ pattern: String) -> NSRegularExpression {
        try! NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
    }

    static let heading = regex("^(#{1,6})[ \\t]+(.+)$")
    static let quote = regex("^(>+)[ \\t]?(.*)$")
    static let list = regex("^[ \\t]*([-*+]|\\d+[.)])[ \\t]+(\\[[ xX]\\][ \\t]+)?")
    private static let taskDone = regex("^[ \\t]*[-*+][ \\t]+\\[[xX]\\][ \\t]+(.*)$")
    static let bold = regex("(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1")
    static let italicStar = regex("(?<![\\*\\w])\\*(?![\\*\\s])(.+?)(?<![\\*\\s])\\*(?![\\*\\w])")
    static let italicUnderscore = regex("(?<![_\\w])_(?![_\\s])(.+?)(?<![_\\s])_(?![_\\w])")
    static let inlineCode = regex("`[^`\\n]+`")
    static let link = regex("!?\\[([^\\]\\n]+)\\]\\(([^)\\n]+)\\)")
    static let mark = regex("==(?=\\S)(.+?)(?<=\\S)==")
    static let strike = regex("~~(?=\\S)(.+?)(?<=\\S)~~")
    private static let rule = regex("^[ \\t]*([-*_])([ \\t]*\\1){2,}[ \\t]*$")
    private static let fence = regex("^```[^\\n]*\\n[\\s\\S]*?^```[ \\t]*$")
    private static let ghost = regex("\\{--([\\s\\S]*?)--\\}")
    private static let note = regex("\\{>>([\\s\\S]*?)<<\\}")
    private static let tk = regex("\\bTK\\b")

    // MARK: Fonts

    func font(size: CGFloat? = nil, bold: Bool = false, italic: Bool = false, mono: Bool = false) -> NSFont {
        let size = size ?? fontSize
        if mono || fontChoice == .mono {
            let base = NSFont.monospacedSystemFont(ofSize: mono && fontChoice != .mono ? size * 0.88 : size, weight: bold ? .semibold : .regular)
            guard italic else { return base }
            let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(.italic))
            return NSFont(descriptor: descriptor, size: base.pointSize) ?? base
        }
        let base = NSFont.systemFont(ofSize: size, weight: bold ? .bold : .regular)
        var descriptor = base.fontDescriptor.withDesign(fontChoice.design) ?? base.fontDescriptor
        if italic { descriptor = descriptor.withSymbolicTraits(descriptor.symbolicTraits.union(.italic)) }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight
        style.paragraphSpacing = fontSize * 0.25
        return style
    }

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: font(), .foregroundColor: theme.text, .paragraphStyle: paragraphStyle]
    }

    // MARK: Highlighting

    func highlightAll(_ storage: NSTextStorage) {
        highlight(storage, in: NSRange(location: 0, length: storage.length))
    }

    /// Re-styles the paragraphs touched by an edit. Small documents are fully re-styled so
    /// multi-line constructs like code fences always stay correct.
    func highlight(_ storage: NSTextStorage, editedRange: NSRange) {
        let ns = storage.string as NSString
        if ns.length < 40_000 {
            highlightAll(storage)
        } else {
            highlight(storage, in: ns.paragraphRange(for: editedRange))
        }
    }

    /// Re-styles just the paragraphs around these ranges (used when the caret moves
    /// between paragraphs and markup needs revealing or hiding).
    func restyleParagraphs(_ storage: NSTextStorage, around ranges: [NSRange]) {
        let ns = storage.string as NSString
        for range in ranges {
            let clamped = NSRange(location: min(range.location, ns.length), length: 0)
            highlight(storage, in: ns.paragraphRange(for: clamped))
        }
    }

    private func highlight(_ storage: NSTextStorage, in range: NSRange) {
        guard range.length > 0 else { return }
        let string = storage.string
        let ns = string as NSString
        let muted = theme.muted
        let accent = theme.accent
        // Markup is collected first and hidden or softened last, after every font is set.
        var markupRanges: [NSRange] = []
        func markup(_ r: NSRange) {
            if r.location != NSNotFound, r.length > 0 { markupRanges.append(r) }
        }
        let reveal = revealRange.map { NSIntersectionRange($0, NSRange(location: 0, length: ns.length)) }
        func revealed(_ r: NSRange) -> Bool {
            guard hideMarkup else { return true }
            guard let reveal else { return false }
            return NSLocationInRange(r.location, reveal) || r.location == NSMaxRange(reveal)
        }

        storage.beginEditing()
        storage.setAttributes(baseAttributes, range: range)

        func each(_ regex: NSRegularExpression, _ body: (NSTextCheckingResult) -> Void) {
            regex.enumerateMatches(in: string, range: range) { match, _, _ in
                if let match { body(match) }
            }
        }
        func color(_ r: NSRange, _ c: NSColor) {
            if r.location != NSNotFound { storage.addAttribute(.foregroundColor, value: c, range: r) }
        }
        /// Wren's own marks (Flow Lock strikes, margin notes, TK) aren't Markdown, so they're
        /// styled in every mode.
        func draftingMarks() {
            // Drafting marks: struck "ghost" text, margin notes and TK placeholders.
            each(Self.ghost) { m in
                storage.addAttributes([.foregroundColor: muted.withAlphaComponent(0.75),
                                       .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                                       .strikethroughColor: theme.accent.withAlphaComponent(0.55)], range: m.range(at: 1))
                for marker in [NSRange(location: m.range.location, length: 3), NSRange(location: NSMaxRange(m.range) - 3, length: 3)] {
                    storage.addAttributes([.foregroundColor: muted.withAlphaComponent(0.35), .font: font(size: fontSize * 0.6)], range: marker)
                    if hideMarkup { markup(marker) }
                }
            }
            each(Self.note) { m in
                storage.addAttributes([.foregroundColor: muted.withAlphaComponent(0.5), .font: font(size: fontSize * 0.6)], range: m.range)
                storage.addAttributes([.foregroundColor: theme.accent, .font: font(size: fontSize * 0.82, italic: true),
                                       .backgroundColor: theme.accent.withAlphaComponent(theme.isDark ? 0.16 : 0.1)], range: m.range(at: 1))
                if hideMarkup {
                    markup(NSRange(location: m.range.location, length: 3))
                    markup(NSRange(location: NSMaxRange(m.range) - 3, length: 3))
                }
            }
            each(Self.tk) { m in
                storage.addAttributes([.foregroundColor: NSColor.white, .backgroundColor: NSColor(hex: 0xE5484D),
                                       .font: font(size: fontSize * 0.85, bold: true)], range: m.range)
            }
        }

        if plain {
            // Plain Markdown: every character exactly as typed, in one font and size.
            draftingMarks()
            storage.endEditing()
            storage.fixAttributes(in: range)
            return
        }

        // Lists: colored markers and a hanging indent so wrapped lines align with the text.
        each(Self.list) { m in
            color(m.range(at: 1), accent)
            color(m.range(at: 2), accent)
            if hideMarkup, m.range(at: 1).length == 1, "-*+".contains(ns.substring(with: m.range(at: 1))) {
                storage.addAttribute(.wrenBullet, value: true, range: m.range(at: 1))
            }
            let prefix = ns.substring(with: m.range)
            let indent = (prefix as NSString).size(withAttributes: [.font: font()]).width
            let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
            style.headIndent = indent
            storage.addAttribute(.paragraphStyle, value: style, range: ns.paragraphRange(for: m.range))
        }
        each(Self.taskDone) { m in
            storage.addAttributes([.strikethroughStyle: NSUnderlineStyle.single.rawValue, .foregroundColor: muted], range: m.range(at: 1))
        }

        // Inline styles.
        each(Self.bold) { m in
            addTraits(storage, m.range, bold: true)
            markup(NSRange(location: m.range.location, length: 2))
            markup(NSRange(location: NSMaxRange(m.range) - 2, length: 2))
        }
        for regex in [Self.italicStar, Self.italicUnderscore] {
            each(regex) { m in
                addTraits(storage, m.range, italic: true)
                markup(NSRange(location: m.range.location, length: 1))
                markup(NSRange(location: NSMaxRange(m.range) - 1, length: 1))
            }
        }
        each(Self.strike) { m in
            storage.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: m.range(at: 1))
            color(m.range(at: 1), muted)
            markup(NSRange(location: m.range.location, length: 2))
            markup(NSRange(location: NSMaxRange(m.range) - 2, length: 2))
        }
        each(Self.mark) { m in
            storage.addAttribute(.backgroundColor, value: accent.withAlphaComponent(theme.isDark ? 0.32 : 0.2), range: m.range(at: 1))
            markup(NSRange(location: m.range.location, length: 2))
            markup(NSRange(location: NSMaxRange(m.range) - 2, length: 2))
        }
        each(Self.link) { m in
            storage.addAttributes([.foregroundColor: accent, .underlineStyle: NSUnderlineStyle.single.rawValue,
                                   .underlineColor: accent.withAlphaComponent(0.4)], range: m.range(at: 1))
            // "[" (or "![") before the text, and "](address)" after it.
            markup(NSRange(location: m.range.location, length: m.range(at: 1).location - m.range.location))
            let textEnd = NSMaxRange(m.range(at: 1))
            markup(NSRange(location: textEnd, length: NSMaxRange(m.range) - textEnd))
        }
        each(Self.inlineCode) { m in
            storage.addAttributes([.font: font(mono: true), .backgroundColor: theme.codeBackground], range: m.range)
            markup(NSRange(location: m.range.location, length: 1))
            markup(NSRange(location: NSMaxRange(m.range) - 1, length: 1))
        }

        // Block styles override inline ones.
        each(Self.quote) { m in
            color(m.range(at: 1), accent)
            color(m.range(at: 2), theme.text.withAlphaComponent(0.72))
            addTraits(storage, m.range(at: 2), italic: true)
            if hideMarkup {
                markup(NSRange(location: m.range.location, length: m.range(at: 2).location - m.range.location))
                let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
                style.firstLineHeadIndent = fontSize * 1.1
                style.headIndent = fontSize * 1.1
                storage.addAttribute(.paragraphStyle, value: style, range: ns.paragraphRange(for: m.range))
            }
        }
        each(Self.heading) { m in
            let level = m.range(at: 1).length
            let scale: [CGFloat] = [1.75, 1.4, 1.2, 1.08, 1, 1]
            storage.addAttributes([.font: font(size: fontSize * scale[level - 1], bold: true), .foregroundColor: theme.heading], range: m.range)
            markup(NSRange(location: m.range.location, length: m.range(at: 2).location - m.range.location))
            let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
            style.paragraphSpacingBefore = level <= 2 ? fontSize * 0.3 : 0
            storage.addAttribute(.paragraphStyle, value: style, range: m.range)
        }
        each(Self.rule) { m in color(m.range, muted) }

        // Images on their own line: quiet markup, with space reserved for the preview below.
        each(MarkdownImage.lineRegex) { m in
            storage.addAttributes([.foregroundColor: muted, .font: font(size: fontSize * 0.78)], range: m.range)
            storage.addAttributes([.foregroundColor: theme.accent, .font: font(size: fontSize * 0.78, italic: true)], range: m.range(at: 1))
            storage.removeAttribute(.underlineStyle, range: m.range)
            // Hidden markup: the picture itself is the content; its code appears when you click in.
            if !revealed(m.range) { markup(m.range) }
            if let size = imageSize?(ns.substring(with: m.range(at: 2))) {
                let style = paragraphStyle.mutableCopy() as! NSMutableParagraphStyle
                style.paragraphSpacing = size.height + 24
                storage.addAttribute(.paragraphStyle, value: style, range: ns.paragraphRange(for: m.range))
            }
        }

        // Front matter: blog metadata, kept quiet.
        if let front = FrontMatter.range(in: string), NSIntersectionRange(front, range).length > 0 {
            let r = NSIntersectionRange(front, range)
            storage.addAttributes([.font: font(size: fontSize * 0.82, mono: true), .foregroundColor: muted], range: r)
            storage.removeAttribute(.strikethroughStyle, range: r)
        }

        draftingMarks()

        // Finally, markup: hidden (when enabled, outside the paragraph being edited) or softened.
        for r in markupRanges where NSMaxRange(r) <= ns.length {
            if revealed(r) {
                storage.addAttribute(.foregroundColor, value: muted, range: r)
            } else {
                storage.addAttributes([.font: Self.hiddenFont, .foregroundColor: NSColor.clear], range: r)
                storage.removeAttribute(.backgroundColor, range: r)
            }
        }

        storage.endEditing()

        // Fences can start outside the edited range, so search the whole document.
        let full = NSRange(location: 0, length: ns.length)
        Self.fence.enumerateMatches(in: string, range: full) { m, _, _ in
            guard let m, NSIntersectionRange(m.range, range).length > 0 else { return }
            storage.addAttributes([.font: font(mono: true), .foregroundColor: theme.text.withAlphaComponent(0.85),
                                   .backgroundColor: theme.codeBackground], range: m.range)
            storage.removeAttribute(.strikethroughStyle, range: m.range)
            storage.removeAttribute(.underlineStyle, range: m.range)
        }
        // Restore fallback fonts for glyphs the chosen font lacks (e.g. ⌘, emoji).
        storage.fixAttributes(in: range)
    }

    private func addTraits(_ storage: NSTextStorage, _ range: NSRange, bold: Bool = false, italic: Bool = false) {
        storage.enumerateAttribute(.font, in: range) { value, run, _ in
            guard let current = value as? NSFont else { return }
            let traits = current.fontDescriptor.symbolicTraits
            let isMono = traits.contains(.monoSpace) && fontChoice != .mono
            let newFont = font(size: isMono ? current.pointSize / 0.88 : current.pointSize,
                               bold: bold || traits.contains(.bold),
                               italic: italic || traits.contains(.italic),
                               mono: isMono)
            storage.addAttribute(.font, value: newFont, range: run)
        }
    }
}
