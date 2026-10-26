import AppKit
import Foundation
import PDFKit
import UniformTypeIdentifiers

/// A small, dependency-free Markdown → HTML converter covering the syntax Wren highlights.
enum MarkdownHTML {
    /// When true (PDF), videos become plain links because print can't play them.
    nonisolated(unsafe) static var videosAsLinks = false

    static func convert(_ markdown: String) -> String {
        let (markdown, notes) = Footnotes.extract(FrontMatter.strip(markdown))
        var html: [String] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var listOrdered = false
        var quote: [String] = []
        var code: [String]? = nil

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p>\(inline(paragraph.joined(separator: " ")))</p>")
            paragraph = []
        }
        func flushList() {
            guard !listItems.isEmpty else { return }
            let tag = listOrdered ? "ol" : "ul"
            html.append("<\(tag)>\n" + listItems.map { "  <li>\($0)</li>" }.joined(separator: "\n") + "\n</\(tag)>")
            listItems = []
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            html.append("<blockquote>\(convert(quote.joined(separator: "\n")))</blockquote>")
            quote = []
        }
        func flushAll() { flushParagraph(); flushList(); flushQuote() }

        for rawLine in markdown.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if var block = code {
                if line.hasPrefix("```") {
                    html.append("<pre><code>\(escape(block.joined(separator: "\n")))</code></pre>")
                    code = nil
                } else {
                    block.append(rawLine)
                    code = block
                }
                continue
            }
            if line.hasPrefix("```") { flushAll(); code = []; continue }
            if line.isEmpty { flushAll(); continue }

            if line.hasPrefix(">") {
                flushParagraph(); flushList()
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }
            flushQuote()

            if let level = headingLevel(line) {
                flushAll()
                let text = line.dropFirst(level).trimmingCharacters(in: .whitespaces)
                html.append("<h\(level)>\(inline(text))</h\(level)>")
            } else if line.count >= 3, Set(line.replacingOccurrences(of: " ", with: "")).count == 1,
                      let ch = line.first, "-*_".contains(ch) {
                flushAll()
                html.append("<hr>")
            } else if let item = listItem(line) {
                flushParagraph()
                if !listItems.isEmpty && listOrdered != item.ordered { flushList() }
                listOrdered = item.ordered
                listItems.append(item.html)
            } else {
                flushList()
                paragraph.append(line)
            }
        }
        if let block = code { html.append("<pre><code>\(escape(block.joined(separator: "\n")))</code></pre>") }
        flushAll()
        return Footnotes.html(html.joined(separator: "\n"), notes: notes, inline: inline)
    }

    private static func headingLevel(_ line: String) -> Int? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return hashes
    }

    private static func listItem(_ line: String) -> (ordered: Bool, html: String)? {
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
            var text = String(line.dropFirst(2))
            if text.hasPrefix("[ ] ") || text.hasPrefix("[x] ") || text.hasPrefix("[X] ") {
                let checked = text.hasPrefix("[ ]") ? "" : " checked"
                text = String(text.dropFirst(4))
                return (false, "<input type=\"checkbox\" disabled\(checked)> \(inline(text))")
            }
            return (false, inline(text))
        }
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return (true, inline(String(line.dropFirst(digits.count + 2))))
        }
        return nil
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static let inlineRules: [(NSRegularExpression, String)] = [
        (try! NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(([^)\\s]+)\\)"), "<a href=\"$2\">$1</a>"),
        (try! NSRegularExpression(pattern: "(\\*\\*|__)(?=\\S)(.+?)(?<=\\S)\\1"), "<strong>$2</strong>"),
        (try! NSRegularExpression(pattern: "(?<![\\*\\w])\\*(?![\\*\\s])(.+?)(?<![\\*\\s])\\*(?![\\*\\w])"), "<em>$1</em>"),
        (try! NSRegularExpression(pattern: "(?<![_\\w])_(?![_\\s])(.+?)(?<![_\\s])_(?![_\\w])"), "<em>$1</em>"),
        (try! NSRegularExpression(pattern: "~~(?=\\S)(.+?)(?<=\\S)~~"), "<del>$1</del>"),
        (try! NSRegularExpression(pattern: "==(?=\\S)(.+?)(?<=\\S)=="), "<mark>$1</mark>"),
    ]

    /// Inline formatting. Code spans are split out first so nothing inside them is touched.
    static func inline(_ text: String) -> String {
        let parts = text.components(separatedBy: "`")
        return parts.enumerated().map { index, part in
            let isCode = index % 2 == 1 && index < parts.count - 1
            if isCode { return "<code>\(escape(part))</code>" }
            var s = media(escape(index % 2 == 1 ? "`" + part : part))
            for (regex, template) in inlineRules {
                s = regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
            }
            return s
        }.joined()
    }

    private static let mediaRegex = try! NSRegularExpression(pattern: "!\\[([^\\]]*)\\]\\(([^)\\s]+)(?:\\s+&quot;[^&]*&quot;)?\\)")

    /// Images become <img>, video files <video>, YouTube links a privacy-friendly embed.
    private static func media(_ escaped: String) -> String {
        guard escaped.contains("![") else { return escaped }
        let result = NSMutableString(string: escaped)
        for m in mediaRegex.matches(in: escaped, range: NSRange(location: 0, length: result.length)).reversed() {
            let alt = result.substring(with: m.range(at: 1))
            let src = result.substring(with: m.range(at: 2))
            let replacement: String
            switch MarkdownImage.kind(of: src) {
            case .youtube(let id):
                replacement = videosAsLinks
                    ? "<a href=\"https://www.youtube.com/watch?v=\(id)\">▶ \(alt.isEmpty ? "Watch on YouTube" : alt)</a>"
                    : "<span class=\"embed\"><iframe src=\"https://www.youtube-nocookie.com/embed/\(id)\" title=\"\(alt)\" allow=\"accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture\" allowfullscreen></iframe></span>"
            case .video:
                replacement = videosAsLinks
                    ? "<a href=\"\(src)\">▶ \(alt.isEmpty ? "Video" : alt)</a>"
                    : "<video controls preload=\"metadata\" src=\"\(src)\" title=\"\(alt)\"></video>"
            case .image:
                replacement = "<img src=\"\(src)\" alt=\"\(alt)\">"
            }
            result.replaceCharacters(in: m.range, with: replacement)
        }
        return result as String
    }

    /// A complete HTML page in the given blog style. The body sits in `#wren-content`
    /// so the live preview can update it in place.
    static func document(title: String, body: String, style: BlogStyle = .classic, print: Bool = false) -> String {
        """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="\(print ? "light" : "light dark")">
        <title>\(escape(title))</title>
        <style>
        \(style.css(print: print))
        </style>
        </head>
        <body>
        <article class="post" id="wren-content">
        \(body)
        </article>
        </body>
        </html>
        """
    }
}

enum Exporter {
    /// A single self-contained file: local images and small videos are embedded as data URIs.
    static func exportHTML(title: String, markdown: String, folder: URL?, style: BlogStyle) -> Bool {
        guard let url = savePanel(title: title, type: .html) else { return false }
        let html = embedMedia(in: MarkdownHTML.document(title: title, body: BlogRenderer.body(markdown: markdown), style: style), folder: folder)
        return (try? html.write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    private static let srcRegex = try! NSRegularExpression(pattern: "<(img|video) ([^>]*?)src=\"([^\"]+)\"")

    static func embedMedia(in html: String, folder: URL?) -> String {
        let result = NSMutableString(string: html)
        for m in srcRegex.matches(in: html, range: NSRange(location: 0, length: result.length)).reversed() {
            let src = result.substring(with: m.range(at: 3)).replacingOccurrences(of: "&amp;", with: "&")
            guard !src.hasPrefix("http"), !src.hasPrefix("data:"),
                  let file = MarkdownImage.resolve(src, relativeTo: folder), file.isFileURL,
                  let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size < 25_000_000,
                  let data = try? Data(contentsOf: file) else { continue }
            let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
            result.replaceCharacters(in: m.range(at: 3), with: "data:\(mime);base64,\(data.base64EncodedString())")
        }
        return result as String
    }

    /// A ready-to-publish folder: index.md with front matter, index.html, and every image or
    /// video the post uses, copied into assets/. It drops straight into Hugo, Jekyll, Astro
    /// or any CMS that takes Markdown.
    static func exportBlog(title: String, markdown: String, folder: URL, style: BlogStyle) -> Bool {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = ImageImporter.slug(title).isEmpty ? "post" : ImageImporter.slug(title)
        panel.prompt = "Export"
        panel.message = "Wren will create a folder containing your post and its media."
        guard panel.runModal() == .OK, let bundle = panel.url else { return false }
        let fm = FileManager.default
        // "Replace" in the save panel means a whole folder here. Never replace one holding
        // the sheet itself (your library, say), and send anything replaced to the Trash.
        if AppModel.relocated(folder, from: bundle, to: bundle) != nil {
            let alert = NSAlert()
            alert.messageText = "Choose another name or place"
            alert.informativeText = "“\(bundle.lastPathComponent)” contains the sheet you're exporting, so Wren won't replace it."
            alert.runModal()
            return false
        }
        do {
            if fm.fileExists(atPath: bundle.path) { try fm.trashItem(at: bundle, resultingItemURL: nil) }
            let assets = bundle.appendingPathComponent(ImageImporter.folderName, isDirectory: true)
            try fm.createDirectory(at: assets, withIntermediateDirectories: true)

            let text = NSMutableString(string: markdown)
            var copied: [URL: String] = [:]
            for ref in MarkdownImage.references(in: markdown).reversed() {
                guard let source = MarkdownImage.resolve(ref.path, relativeTo: folder), source.isFileURL,
                      fm.fileExists(atPath: source.path) else { continue }
                var name = copied[source]
                if name == nil {
                    var candidate = source.lastPathComponent
                    var n = 2
                    while fm.fileExists(atPath: assets.appendingPathComponent(candidate).path) {
                        candidate = "\(source.deletingPathExtension().lastPathComponent)-\(n).\(source.pathExtension)"
                        n += 1
                    }
                    try fm.copyItem(at: source, to: assets.appendingPathComponent(candidate))
                    copied[source] = candidate
                    name = candidate
                }
                text.replaceCharacters(in: ref.range, with: "![\(ref.alt)](\(ImageImporter.folderName)/\(name!))")
            }

            var post = text as String
            if FrontMatter.range(in: post) == nil { post = FrontMatter.make(title: title) + post }
            try post.write(to: bundle.appendingPathComponent("index.md"), atomically: true, encoding: .utf8)
            let html = MarkdownHTML.document(title: title, body: BlogRenderer.body(markdown: post), style: style)
            try html.write(to: bundle.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
            if copied.isEmpty { try? fm.removeItem(at: assets) }
            NSWorkspace.shared.activateFileViewerSelecting([bundle])
            return true
        } catch {
            return false
        }
    }

    static func exportMarkdown(title: String, markdown: String) -> Bool {
        let type = UTType(filenameExtension: "md") ?? .plainText
        guard let url = savePanel(title: title, type: type) else { return false }
        return (try? markdown.write(to: url, atomically: true, encoding: .utf8)) != nil
    }

    static func exportPDF(title: String, markdown: String, folder: URL?, style: BlogStyle) -> Bool {
        guard let url = savePanel(title: title, type: .pdf),
              let data = pdfData(html: printHTML(title: title, body: printBody(markdown), style: style, folder: folder), title: title) else { return false }
        return (try? data.write(to: url)) != nil
    }

    /// A Word document, for editors, publishers and anyone who lives in Microsoft Word.
    static func exportWord(title: String, markdown: String, folder: URL?, style: BlogStyle) -> Bool {
        guard let url = savePanel(title: title, type: UTType(filenameExtension: "docx") ?? .data),
              let data = wordData(html: printHTML(title: title, body: printBody(markdown), style: style, folder: folder)) else { return false }
        return (try? data.write(to: url)) != nil
    }

    // MARK: Books

    enum CompileFormat: String, CaseIterable, Identifiable {
        case word, pdf, epub, html, markdown
        var id: String { rawValue }
        var label: String {
            switch self {
            case .word: "Word (.docx)"
            case .pdf: "Print-ready PDF"
            case .epub: "Ebook (EPUB)"
            case .html: "Web page (.html)"
            case .markdown: "Markdown (.md)"
            }
        }
        var type: UTType {
            switch self {
            case .word: UTType(filenameExtension: "docx") ?? .data
            case .pdf: .pdf
            case .epub: UTType(filenameExtension: "epub") ?? .data
            case .html: .html
            case .markdown: UTType(filenameExtension: "md") ?? .plainText
            }
        }
    }

    /// Stitches a book's chapters into one manuscript. In PDFs every chapter starts on a new page.
    static func compileBook(title: String, author: String?, chapters: [String], titlePage: Bool,
                            format: CompileFormat, style: BlogStyle, folder: URL, layout: BookSettings = BookSettings()) -> Bool {
        guard let url = savePanel(title: title, type: format.type) else { return false }
        let cleaned = chapters.map { FrontMatter.strip(Ghost.clean($0)).trimmingCharacters(in: .whitespacesAndNewlines) }
        let byline = author.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
        let titleMarkdown = "# \(title)" + (byline.map { "\n\n*by \($0)*" } ?? "")
        let titleHTML = "<div class=\"title-page\"><h1>\(MarkdownHTML.escape(title))</h1>" + (byline.map { "<p class=\"meta\">by \(MarkdownHTML.escape($0))</p>" } ?? "") + "</div>"

        let data: Data?
        switch format {
        case .markdown:
            let parts = (titlePage ? [titleMarkdown] : []) + cleaned
            data = parts.joined(separator: "\n\n---\n\n").data(using: .utf8)
        case .html:
            let sections = cleaned.map { "<section class=\"chapter\">\n\(MarkdownHTML.convert($0))\n</section>" }
            let body = (titlePage ? titleHTML : "") + sections.joined(separator: "\n")
            let page = MarkdownHTML.document(title: title, body: body, style: style).replacingOccurrences(of: "</style>", with: bookCSS + "</style>")
            data = embedMedia(in: page, folder: folder).data(using: .utf8)
        case .epub:
            data = EPUBBuilder.build(title: title, author: byline, chapters: cleaned, titlePage: titlePage, folder: folder)
        case .pdf:
            // Typeset as a printed book: trim size, mirrored margins, chapters on new pages.
            var settings = layout
            settings.titlePage = titlePage
            data = BookTypesetter(title: title, author: byline, chapters: cleaned, settings: settings).pdfData()
        case .word:
            let body = ((titlePage ? [titleHTML] : []) + cleaned.map { printBody($0) }).joined(separator: "\n<hr>\n")
            data = wordData(html: printHTML(title: title, body: body, style: style, folder: folder))
        }
        guard let data, (try? data.write(to: url)) != nil else { return false }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        return true
    }

    private static let bookCSS = """
    .title-page { min-height: 60vh; display: flex; flex-direction: column; justify-content: center; text-align: center; }
    .title-page h1 { font-size: 3em; }
    .chapter { break-before: page; page-break-before: always; padding-top: 2em; }
    """

    // MARK: Print helpers

    private static func printBody(_ markdown: String) -> String {
        MarkdownHTML.videosAsLinks = true
        defer { MarkdownHTML.videosAsLinks = false }
        return BlogRenderer.body(markdown: markdown)
    }

    private static func printHTML(title: String, body: String, style: BlogStyle, folder: URL?) -> String {
        embedMedia(in: MarkdownHTML.document(title: title, body: body, style: style, print: true), folder: folder)
    }

    /// A single sheet as a PDF: A4, about an inch of margin, page numbers from page two.
    private static let sheetLayout = BookSettings(trim: .a4, twoSided: false, chaptersOnRight: false, titlePage: false,
                                                  pageNumbers: true, runningHeads: false)

    /// HTML → attributed text, with oversized images shrunk to fit the page.
    private static func attributed(html: String) -> NSMutableAttributedString? {
        guard let data = html.data(using: .utf8), let imported = NSAttributedString(html: data, documentAttributes: nil) else { return nil }
        let width = BookTypesetter.textWidth(for: sheetLayout)
        // A little under the full height: the line an image sits on needs some room too.
        let height = BookTypesetter.textHeight(for: sheetLayout) * 0.9
        let attributed = NSMutableAttributedString(attributedString: imported)
        attributed.enumerateAttribute(.attachment, in: NSRange(location: 0, length: attributed.length)) { value, _, _ in
            guard let attachment = value as? NSTextAttachment else { return }
            var size = attachment.bounds.size
            if size == .zero {
                size = attachment.image?.size
                    ?? attachment.fileWrapper?.regularFileContents.flatMap { NSImage(data: $0)?.size }
                    ?? .zero
            }
            guard size.width > 0, size.height > 0 else { return }
            let fit = min(1, width / size.width, height / size.height)
            guard fit < 1 else { return }
            attachment.bounds = CGRect(x: 0, y: 0, width: size.width * fit, height: size.height * fit)
        }
        return attributed
    }

    private static func pdfData(html: String, title: String = "") -> Data? {
        guard let text = attributed(html: html) else { return nil }
        return BookTypesetter(title: title, document: text, settings: sheetLayout).pdfData()
    }

    private static func wordData(html: String) -> Data? {
        guard let text = attributed(html: html) else { return nil }
        return try? text.data(from: NSRange(location: 0, length: text.length),
                              documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
    }

    /// The post as formatted text for editors that only take a paste (Substack, Medium):
    /// headings, emphasis, links, lists and images come across. The title stays out, since
    /// both have their own title field.
    static func copyRich(_ post: PreparedPost, folder: URL?) {
        let html = "<html><head><meta charset=\"utf-8\"></head><body>"
            + embedMedia(in: MarkdownHTML.convert(post.markdown), folder: folder) + "</body></html>"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(html, forType: .html)
        if let data = html.data(using: .utf8), let attributed = NSAttributedString(html: data, documentAttributes: nil),
           let rtf = try? attributed.data(from: NSRange(location: 0, length: attributed.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) {
            pasteboard.setData(rtf, forType: .rtf)
        }
        pasteboard.setString(post.markdown, forType: .string)
    }

    static func copyHTML(markdown: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(MarkdownHTML.convert(markdown), forType: .string)
    }

    private static func savePanel(title: String, type: UTType) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = LibraryStore.sanitize(title).isEmpty ? "Untitled" : LibraryStore.sanitize(title)
        return panel.runModal() == .OK ? panel.url : nil
    }
}
