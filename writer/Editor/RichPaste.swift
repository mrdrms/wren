import AppKit

/// Turns formatted text (from Google Docs, Word, Pages or a web page) into Markdown, so
/// pasting keeps headings, bold, italics, links and lists without anyone typing a symbol.
enum RichPaste {
    /// Markdown for the rich text on the pasteboard, or nil when there's nothing worth converting.
    static func markdown(from pasteboard: NSPasteboard) -> String? {
        var attributed: NSAttributedString?
        if let rtf = pasteboard.data(forType: .rtf) {
            attributed = NSAttributedString(rtf: rtf, documentAttributes: nil)
        } else if let html = pasteboard.data(forType: .html) {
            attributed = NSAttributedString(html: html, documentAttributes: nil)
        }
        guard let attributed, attributed.length > 0 else { return nil }
        let result = markdown(from: attributed)
        // No formatting gained over the plain text: let the normal paste handle it.
        let plain = pasteboard.string(forType: .string) ?? ""
        let same = result.trimmingCharacters(in: .whitespacesAndNewlines) == plain.trimmingCharacters(in: .whitespacesAndNewlines)
        return same ? nil : result
    }

    private struct Style: Equatable {
        var bold = false, italic = false, strike = false
        var link: URL?
    }

    static func markdown(from text: NSAttributedString) -> String {
        let ns = text.string as NSString
        let full = NSRange(location: 0, length: ns.length)

        // Code copied from an editor arrives as rich text too; keep it verbatim.
        var allMono = true
        text.enumerateAttribute(.font, in: full) { value, range, stop in
            let isMono = (value as? NSFont)?.isFixedPitch ?? false
            if !isMono, ns.substring(with: range).contains(where: { !$0.isWhitespace }) { allMono = false; stop.pointee = true }
        }
        if allMono { return text.string }

        let bodySize = dominantFontSize(text)
        var blocks: [(markdown: String, isListItem: Bool)] = []
        var numbering: [Int: Int] = [:]

        ns.enumerateSubstrings(in: full, options: .byParagraphs) { _, range, _, _ in
            let raw = ns.substring(with: range)
            guard raw.contains(where: { !$0.isWhitespace && $0 != "\u{FFFC}" }) else {
                numbering.removeAll()
                return
            }
            let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            var contentRange = range
            var prefix = ""
            var isListItem = false

            if let lists = style?.textLists, let list = lists.last {
                isListItem = true
                // Imported lists include their own "\t•\t" or "\t1.\t" marker text; drop it.
                if let marker = try? NSRegularExpression(pattern: "^\\t?[^\\t]{0,6}\\t").firstMatch(in: raw, range: NSRange(location: 0, length: (raw as NSString).length)) {
                    contentRange = NSRange(location: range.location + marker.range.length, length: range.length - marker.range.length)
                }
                let depth = lists.count - 1
                let indent = String(repeating: "  ", count: depth)
                let format = list.markerFormat.rawValue.lowercased()
                if format.contains("decimal") || format.contains("roman") || format.contains("alpha") {
                    numbering[depth, default: 0] += 1
                    prefix = indent + "\(numbering[depth]!). "
                } else {
                    prefix = indent + "- "
                }
            } else {
                numbering.removeAll()
                let size = largestFontSize(text, in: range)
                if size >= bodySize * 1.6 { prefix = "# " } else if size >= bodySize * 1.3 { prefix = "## " } else if size >= bodySize * 1.12 { prefix = "### " }
            }

            let isHeading = prefix.hasPrefix("#")
            let inline = inlineMarkdown(text, in: contentRange, ignoreBold: isHeading)
            guard !inline.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            blocks.append((prefix + inline.trimmingCharacters(in: .whitespaces), isListItem))
        }

        var result = ""
        for (index, block) in blocks.enumerated() {
            if index > 0 { result += (block.isListItem && blocks[index - 1].isListItem) ? "\n" : "\n\n" }
            result += block.markdown
        }
        return result
    }

    private static func inlineMarkdown(_ text: NSAttributedString, in range: NSRange, ignoreBold: Bool) -> String {
        var runs: [(String, Style)] = []
        text.enumerateAttributes(in: range) { attrs, runRange, _ in
            var style = Style()
            if let font = attrs[.font] as? NSFont {
                let traits = font.fontDescriptor.symbolicTraits
                style.bold = !ignoreBold && traits.contains(.bold)
                style.italic = traits.contains(.italic)
            }
            if let strike = attrs[.strikethroughStyle] as? Int, strike != 0 { style.strike = true }
            if let link = attrs[.link] as? URL { style.link = link } else if let link = attrs[.link] as? String { style.link = URL(string: link) }
            let piece = (text.string as NSString).substring(with: runRange).replacingOccurrences(of: "\u{FFFC}", with: "")
            if let last = runs.last, last.1 == style {
                runs[runs.count - 1].0 += piece
            } else {
                runs.append((piece, style))
            }
        }

        return runs.map { piece, style -> String in
            // Markers hug the words; surrounding spaces stay outside them.
            let leading = String(piece.prefix { $0.isWhitespace })
            let trailing = String(piece.reversed().prefix { $0.isWhitespace }.reversed())
            var core = piece.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { return piece }
            if style.strike { core = "~~\(core)~~" }
            if style.italic { core = "*\(core)*" }
            if style.bold { core = "**\(core)**" }
            if let link = style.link, ["http", "https", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                core = "[\(core)](\(link.absoluteString))"
            }
            return leading + core + trailing
        }.joined()
    }

    /// The font size most of the text uses: the "body" size headings are measured against.
    private static func dominantFontSize(_ text: NSAttributedString) -> CGFloat {
        var weights: [CGFloat: Int] = [:]
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let size = (value as? NSFont)?.pointSize { weights[size.rounded(), default: 0] += range.length }
        }
        return weights.max { $0.value < $1.value }?.key ?? 12
    }

    private static func largestFontSize(_ text: NSAttributedString, in range: NSRange) -> CGFloat {
        var largest: CGFloat = 0
        text.enumerateAttribute(.font, in: range) { value, run, _ in
            let piece = (text.string as NSString).substring(with: run)
            if piece.contains(where: { !$0.isWhitespace }), let size = (value as? NSFont)?.pointSize { largest = max(largest, size) }
        }
        return largest
    }
}
