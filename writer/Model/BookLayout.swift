import AppKit

/// Common print-on-demand trim sizes, in points (72 per inch).
enum TrimSize: String, CaseIterable, Identifiable, Codable {
    case pocket, digest, trade, a5, a4

    var id: String { rawValue }
    var label: String {
        switch self {
        case .pocket: "Pocket · 5 × 8 in"
        case .digest: "Digest · 5.5 × 8.5 in"
        case .trade: "Trade · 6 × 9 in"
        case .a5: "A5 · 148 × 210 mm"
        case .a4: "A4 · 210 × 297 mm"
        }
    }
    var size: NSSize {
        switch self {
        case .pocket: NSSize(width: 360, height: 576)
        case .digest: NSSize(width: 396, height: 612)
        case .trade: NSSize(width: 432, height: 648)
        case .a5: NSSize(width: 420, height: 595)
        case .a4: NSSize(width: 595, height: 842)
        }
    }
}

struct BookSettings: Equatable, Codable {
    var trim: TrimSize = .trade
    /// Mirrored margins for binding: a wider inner margin on every page.
    var twoSided = true
    /// Every chapter opens on a right-hand page, as in most printed books.
    var chaptersOnRight = true
    var titlePage = true
    var pageNumbers = true
    var runningHeads = true
    var fontSize: CGFloat = 11
}

/// Lays a book out into pages: the same pages drive the spread preview and the PDF, so
/// what you see is exactly what you print.
final class BookTypesetter {
    enum Content {
        case title
        case blank
        case text(chapter: Int, container: NSTextContainer, opensChapter: Bool)
    }

    struct Page {
        /// 1-based, as printed. Odd pages are right-hand pages.
        let number: Int
        let content: Content
        var isRecto: Bool { number % 2 == 1 }
    }

    let settings: BookSettings
    let title: String
    let author: String?
    private(set) var pages: [Page] = []
    private var chapterTitles: [String] = []
    /// Kept alive: the pages' text containers belong to these.
    private var layouts: [NSLayoutManager] = []
    private var storages: [NSTextStorage] = []

    var pageSize: NSSize { settings.trim.size }

    init(title: String, author: String?, chapters: [String], settings: BookSettings) {
        self.title = title
        self.author = author
        self.settings = settings
        typeset(chapters)
    }

    /// A single document that's already styled (an exported sheet): just pages, margins
    /// and page numbers.
    init(title: String, document: NSAttributedString, settings: BookSettings) {
        self.title = title
        self.author = nil
        self.settings = settings
        chapterTitles = [title]
        var number = 1
        layOut(document, chapter: 0, number: &number)
    }

    // MARK: Geometry

    /// Margins scale with the page so small trims don't drown in white space.
    private var scale: CGFloat { pageSize.width / 432 }
    private var top: CGFloat { 58 * scale }
    private var bottom: CGFloat { 62 * scale }
    private var inner: CGFloat { (settings.twoSided ? 62 : 54) * scale }
    private var outer: CGFloat { (settings.twoSided ? 46 : 54) * scale }
    private var textSize: NSSize { NSSize(width: pageSize.width - inner - outer, height: pageSize.height - top - bottom) }

    private func textOrigin(recto: Bool) -> NSPoint {
        NSPoint(x: !settings.twoSided || recto ? inner : outer, y: top)
    }

    // MARK: Typesetting

    private func typeset(_ chapters: [String]) {
        var number = 1
        if settings.titlePage {
            pages.append(Page(number: number, content: .title))
            number += 1
        }
        let typography = BookTypography(fontSize: settings.fontSize * min(1.15, max(0.9, scale)), openingDrop: textSize.height * 0.28)
        for (index, markdown) in chapters.enumerated() {
            let (text, chapterTitle) = typography.attributed(markdown)
            chapterTitles.append(chapterTitle ?? "")
            guard text.length > 0 else { continue }
            if settings.twoSided && settings.chaptersOnRight && number % 2 == 0 {
                pages.append(Page(number: number, content: .blank))
                number += 1
            }
            layOut(text, chapter: index, number: &number)
        }
    }

    /// Flows text into as many pages as it needs.
    private func layOut(_ text: NSAttributedString, chapter: Int, number: inout Int) {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        storages.append(storage)
        layouts.append(layout)
        var first = true
        while true {
            let container = NSTextContainer(size: textSize)
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            let range = layout.glyphRange(for: container)
            // A page that takes nothing would loop forever (an oversized image, say).
            if range.length == 0 && !first { layout.removeTextContainer(at: layout.textContainers.count - 1); break }
            pages.append(Page(number: number, content: .text(chapter: chapter, container: container, opensChapter: first)))
            number += 1
            first = false
            if NSMaxRange(range) >= layout.numberOfGlyphs { break }
        }
    }

    /// The width text gets on a page, for sizing images before layout.
    static func textWidth(for settings: BookSettings) -> CGFloat {
        // Inner and outer margins always add up to 108 points at the 6 × 9 reference width.
        settings.trim.size.width - 108 * settings.trim.size.width / 432
    }

    // MARK: Drawing

    /// Draws one page into the current graphics context, which must be flipped.
    func draw(_ page: Page) {
        NSColor.white.setFill()
        NSRect(origin: .zero, size: pageSize).fill()
        let typography = BookTypography(fontSize: settings.fontSize * min(1.15, max(0.9, scale)), openingDrop: 0)
        switch page.content {
        case .blank:
            break
        case .title:
            drawTitlePage(typography)
        case .text(let chapter, let container, let opensChapter):
            guard let layout = container.layoutManager else { return }
            let range = layout.glyphRange(for: container)
            layout.drawBackground(forGlyphRange: range, at: textOrigin(recto: page.isRecto))
            layout.drawGlyphs(forGlyphRange: range, at: textOrigin(recto: page.isRecto))
            guard !opensChapter else { return }
            if settings.runningHeads {
                let head = page.isRecto || !settings.twoSided ? chapterTitles[chapter] : title
                drawCentered(head.uppercased(), font: typography.small, color: .darkGray, kern: 1.2, y: top * 0.45, recto: page.isRecto)
            }
            if settings.pageNumbers {
                drawCentered("\(page.number)", font: typography.small, color: .darkGray, kern: 0,
                             y: pageSize.height - bottom * 0.55, recto: page.isRecto)
            }
        }
    }

    private func drawTitlePage(_ typography: BookTypography) {
        let titleFont = typography.font(size: typography.fontSize * 2.6)
        let titleText = NSAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: NSColor.black,
                                                                         .paragraphStyle: Self.centered])
        let box = NSRect(x: inner, y: pageSize.height * 0.3, width: textSize.width, height: pageSize.height * 0.3)
        titleText.draw(with: box, options: [.usesLineFragmentOrigin])
        if let author, !author.isEmpty {
            let byline = NSAttributedString(string: author, attributes: [.font: typography.font(size: typography.fontSize * 1.3, italic: true),
                                                                          .foregroundColor: NSColor.darkGray, .paragraphStyle: Self.centered])
            let height = titleText.boundingRect(with: NSSize(width: textSize.width, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin]).height
            byline.draw(with: NSRect(x: inner, y: box.minY + height + 28 * scale, width: textSize.width, height: 80),
                        options: [.usesLineFragmentOrigin])
        }
    }

    private func drawCentered(_ string: String, font: NSFont, color: NSColor, kern: CGFloat, y: CGFloat, recto: Bool) {
        let text = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern, .paragraphStyle: Self.centered])
        text.draw(with: NSRect(x: textOrigin(recto: recto).x, y: y, width: textSize.width, height: font.pointSize * 2),
                  options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private static let centered: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        return style
    }()

    // MARK: Output

    func pdfData() -> Data? {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: pageSize)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, [kCGPDFContextTitle: title] as CFDictionary) else { return nil }
        for page in pages {
            context.beginPDFPage(nil)
            context.translateBy(x: 0, y: pageSize.height)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            draw(page)
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    func image(of page: Page) -> NSImage {
        NSImage(size: pageSize, flipped: true) { [self] _ in
            draw(page)
            return true
        }
    }
}

/// Book typography for prose: a book serif, justified and hyphenated, indented paragraphs
/// with no gaps between them, and chapters that open a third of the way down the page.
struct BookTypography {
    let fontSize: CGFloat
    /// Space above a chapter's opening heading.
    let openingDrop: CGFloat

    var small: NSFont { font(size: fontSize * 0.78) }

    func font(size: CGFloat, bold: Bool = false, italic: Bool = false, mono: Bool = false) -> NSFont {
        var font = mono ? NSFont.monospacedSystemFont(ofSize: size * 0.9, weight: .regular)
            : NSFont(name: "Iowan Old Style", size: size) ?? NSFont(name: "Georgia", size: size) ?? .systemFont(ofSize: size)
        if bold { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
        if italic { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
        return font
    }

    private func paragraph(indent: Bool, alignment: NSTextAlignment = .justified, before: CGFloat = 0, after: CGFloat = 0,
                           head: CGFloat = 0) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineHeightMultiple = 1.18
        style.hyphenationFactor = alignment == .justified ? 0.9 : 0
        style.firstLineHeadIndent = head + (indent ? fontSize * 1.5 : 0)
        style.headIndent = head
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        return style
    }

    /// The chapter as print-ready text, plus its title (the first heading) for running heads.
    func attributed(_ markdown: String) -> (NSAttributedString, String?) {
        let output = NSMutableAttributedString()
        var chapterTitle: String?
        // The first paragraph after a heading or scene break isn't indented.
        var indentNext = false
        var inCode = false
        var code: [String] = []

        func append(_ text: NSAttributedString) {
            if output.length > 0 { output.append(NSAttributedString(string: "\n")) }
            output.append(text)
        }

        for block in blocks(markdown) {
            if block.hasPrefix("```") {
                inCode.toggle()
                if !inCode {
                    let style = paragraph(indent: false, alignment: .left, before: fontSize * 0.6, after: fontSize * 0.6, head: fontSize)
                    append(NSAttributedString(string: code.joined(separator: "\n"), attributes: [.font: font(size: fontSize, mono: true), .paragraphStyle: style]))
                    code = []
                    indentNext = false
                }
                continue
            }
            if inCode { code.append(block); continue }

            let trimmed = block.trimmingCharacters(in: .whitespaces)
            if let level = headingLevel(trimmed) {
                let text = String(trimmed.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                let opening = chapterTitle == nil && output.length == 0
                if opening { chapterTitle = plain(text) }
                let size = opening ? fontSize * 1.9 : fontSize * (level <= 2 ? 1.25 : 1.08)
                let style = opening
                    ? paragraph(indent: false, alignment: .center, before: openingDrop, after: fontSize * 3)
                    : paragraph(indent: false, alignment: .center, before: fontSize * 1.6, after: fontSize * 0.9)
                append(inline(text, size: size, style: style, bold: !opening))
                indentNext = false
            } else if trimmed.range(of: #"^(\* *\* *\*[\* ]*|-{3,}|_{3,})$"#, options: .regularExpression) != nil {
                let style = paragraph(indent: false, alignment: .center, before: fontSize * 0.8, after: fontSize * 0.8)
                append(NSAttributedString(string: "⁂", attributes: [.font: font(size: fontSize), .paragraphStyle: style, .foregroundColor: NSColor.darkGray]))
                indentNext = false
            } else if trimmed.hasPrefix("![") {
                continue // images don't belong in a print novel; keep the text flowing
            } else if trimmed.hasPrefix(">") {
                let text = trimmed.split(separator: "\n").map { $0.drop(while: { $0 == ">" || $0 == " " }) }.joined(separator: " ")
                let style = paragraph(indent: false, before: fontSize * 0.5, after: fontSize * 0.5, head: fontSize * 1.5)
                append(inline(text, size: fontSize, style: style, italic: true))
                indentNext = false
            } else if let item = listItem(trimmed) {
                let style = paragraph(indent: false, alignment: .left, head: fontSize * 1.5)
                let mutable = NSMutableParagraphStyle()
                mutable.setParagraphStyle(style)
                mutable.firstLineHeadIndent = fontSize * 0.5
                mutable.tabStops = [NSTextTab(textAlignment: .left, location: fontSize * 1.5)]
                append(inline("\(item.marker)\t\(item.text)", size: fontSize, style: mutable))
                indentNext = true
            } else {
                let text = trimmed.split(separator: "\n").joined(separator: " ")
                append(inline(text, size: fontSize, style: paragraph(indent: indentNext)))
                indentNext = true
            }
        }
        return (output, chapterTitle)
    }

    /// Paragraph blocks, split on blank lines; fenced code lines come through one by one.
    private func blocks(_ markdown: String) -> [String] {
        var result: [String] = []
        var current: [String] = []
        var inCode = false
        func flush() {
            if !current.isEmpty { result.append(current.joined(separator: "\n")); current = [] }
        }
        for line in markdown.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                flush()
                result.append("```")
                inCode.toggle()
            } else if inCode {
                result.append(line)
            } else if trimmed.isEmpty {
                flush()
            } else if headingLevel(trimmed) != nil || listItem(trimmed) != nil {
                // Headings and list items stand alone even without blank lines around them.
                flush()
                result.append(trimmed)
            } else {
                current.append(line)
            }
        }
        flush()
        return result
    }

    private func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private func listItem(_ line: String) -> (marker: String, text: String)? {
        if let match = line.range(of: #"^[-*+] +"#, options: .regularExpression) {
            return ("•", String(line[match.upperBound...]))
        }
        if let match = line.range(of: #"^\d+[.)] +"#, options: .regularExpression) {
            return (String(line[..<match.upperBound]).trimmingCharacters(in: .whitespaces), String(line[match.upperBound...]))
        }
        return nil
    }

    private func plain(_ markdown: String) -> String {
        (try? AttributedString(markdown: markdown)).map { String($0.characters) } ?? markdown
    }

    /// Inline Markdown (emphasis, strong, code, strikethrough, links) in book fonts.
    private func inline(_ markdown: String, size: CGFloat, style: NSParagraphStyle, bold: Bool = false, italic: Bool = false) -> NSAttributedString {
        let source = markdown.replacingOccurrences(of: "==", with: "")
        let parsed = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(source)
        let output = NSMutableAttributedString()
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font(size: size, bold: bold || intent.contains(.stronglyEmphasized), italic: italic || intent.contains(.emphasized),
                            mono: intent.contains(.code)),
                .foregroundColor: NSColor.black,
                .paragraphStyle: style,
            ]
            if intent.contains(.strikethrough) { attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return output
    }
}
