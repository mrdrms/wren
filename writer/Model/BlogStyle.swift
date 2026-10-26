import AppKit
import Foundation
import SwiftUI

/// How a post looks when published. The same CSS drives the live preview and every export,
/// so what you see while writing is what readers get.
enum BlogStyle: String, CaseIterable, Identifiable {
    case classic, modern, editorial, mono, terminal

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var blurb: String {
        switch self {
        case .classic: "Warm serif, the Wren look"
        case .modern: "Clean sans-serif, like a product blog"
        case .editorial: "Big serif type with a drop cap"
        case .mono: "Monospaced, for dev logs"
        case .terminal: "Green phosphor on black, for security and hacker blogs"
        }
    }

    private struct Palette {
        let bg, fg, heading, muted, accent, codeBg, mark: String
    }

    private struct Typography {
        let body, heading, size, lineHeight, measure, headingWeight: String
        let extra: String
    }

    private var light: Palette {
        switch self {
        case .classic: Palette(bg: "#fbf8f3", fg: "#2b2a28", heading: "#1c1b19", muted: "#6b655d", accent: "#e8590c", codeBg: "#f1ebe2", mark: "#ffe3cc")
        case .modern: Palette(bg: "#ffffff", fg: "#1f2328", heading: "#0b0d10", muted: "#59636e", accent: "#2563eb", codeBg: "#f3f4f6", mark: "#dbe7ff")
        case .editorial: Palette(bg: "#ffffff", fg: "#242424", heading: "#111111", muted: "#6b6b6b", accent: "#1a8917", codeBg: "#f2f2f2", mark: "#d9f2dc")
        case .mono: Palette(bg: "#f7f7f5", fg: "#222222", heading: "#000000", muted: "#77736d", accent: "#d6336c", codeBg: "#ecebe7", mark: "#ffd6e5")
        case .terminal: Self.phosphor
        }
    }

    /// Terminal is always a dark screen, whatever the reader's system appearance.
    private static let phosphor = Palette(bg: "#070b08", fg: "#b9f5c4", heading: "#dcffe4", muted: "#4f8a5c", accent: "#39ff88", codeBg: "#0f1d14", mark: "#1f5a34")

    private var dark: Palette {
        switch self {
        case .classic: Palette(bg: "#1b1a18", fg: "#e7e2da", heading: "#fbf7f0", muted: "#a39c92", accent: "#ff8a4c", codeBg: "#2a2825", mark: "#5a3a22")
        case .modern: Palette(bg: "#0d1117", fg: "#e6edf3", heading: "#ffffff", muted: "#8d96a0", accent: "#58a6ff", codeBg: "#161b22", mark: "#1f3a63")
        case .editorial: Palette(bg: "#121212", fg: "#e6e6e6", heading: "#ffffff", muted: "#9a9a9a", accent: "#3dbb5a", codeBg: "#1e1e1e", mark: "#1f4626")
        case .mono: Palette(bg: "#111111", fg: "#dddddd", heading: "#ffffff", muted: "#8a8680", accent: "#ff6b9d", codeBg: "#1c1c1c", mark: "#5c1f36")
        case .terminal: Self.phosphor
        }
    }

    private var type: Typography {
        let serif = "\"New York\", \"Iowan Old Style\", Charter, Georgia, serif"
        let sans = "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"Helvetica Neue\", sans-serif"
        let mono = "\"SF Mono\", ui-monospace, Menlo, monospace"
        switch self {
        case .classic:
            return Typography(body: serif, heading: sans, size: "19px", lineHeight: "1.7", measure: "680px", headingWeight: "700", extra: "")
        case .modern:
            return Typography(body: sans, heading: sans, size: "18px", lineHeight: "1.65", measure: "720px", headingWeight: "800",
                              extra: "h1, h2, h3 { letter-spacing: -0.02em; }")
        case .editorial:
            return Typography(body: "Charter, \"Iowan Old Style\", Georgia, serif", heading: serif, size: "21px", lineHeight: "1.75",
                              measure: "700px", headingWeight: "700",
                              extra: ".post > p:first-of-type::first-letter { float: left; font-size: 3.4em; line-height: 0.9; padding: 0.06em 0.1em 0 0; font-weight: 700; }")
        case .mono:
            return Typography(body: mono, heading: mono, size: "15px", lineHeight: "1.75", measure: "720px", headingWeight: "700",
                              extra: "h1::before { content: \"# \"; opacity: .45; } h2::before { content: \"## \"; opacity: .4; }")
        case .terminal:
            return Typography(body: mono, heading: mono, size: "15px", lineHeight: "1.75", measure: "760px", headingWeight: "700", extra: """
                body { text-shadow: 0 0 6px rgba(57,255,136,.18); background-image: repeating-linear-gradient(0deg, rgba(0,0,0,.18) 0 1px, transparent 1px 3px); }
                .post { border-left: 1px solid rgba(57,255,136,.18); }
                .post-header::before { content: "user@wren:~$ cat post.md"; display: block; color: #4f8a5c; font-size: .85em; margin-bottom: 1.4em; }
                h1::before { content: "$ "; color: #39ff88; }
                h2::before { content: "## "; color: #4f8a5c; }
                h3::before { content: "### "; color: #4f8a5c; }
                a { text-decoration-style: dotted; }
                pre { border: 1px solid rgba(57,255,136,.25); }
                ::selection { background: #39ff88; color: #070b08; }
                """)
        }
    }

    /// The page color readers will see, for the area around the preview.
    func pageBackground(dark: Bool) -> Color {
        let hex = UInt32((dark ? self.dark : light).bg.dropFirst(), radix: 16) ?? 0xFFFFFF
        return Color(nsColor: NSColor(hex: hex))
    }

    private func colors(_ p: Palette) -> String {
        """
        html, body { background: \(p.bg); color: \(p.fg); }
        h1, h2, h3, h4, h5, h6 { color: \(p.heading); }
        a { color: \(p.accent); }
        .meta, blockquote, figcaption { color: \(p.muted); }
        blockquote { border-left-color: \(p.accent); }
        code, pre { background: \(p.codeBg); }
        mark { background: \(p.mark); }
        hr::after { color: \(p.muted); }
        """
    }

    /// Full CSS. `print` drops the dark-mode block (PDF pages are always light).
    func css(print: Bool = false) -> String {
        let t = type
        let base = """
        * { box-sizing: border-box; }
        html { -webkit-text-size-adjust: 100%; }
        body { margin: 0; font-family: \(t.body); font-size: \(t.size); line-height: \(t.lineHeight); -webkit-font-smoothing: antialiased; }
        .post { max-width: \(t.measure); margin: 0 auto; padding: 64px 24px 120px; }
        .post-header { margin-bottom: 2.4em; }
        .post-header h1 { margin: 0 0 0.35em; }
        .meta { font-family: -apple-system, sans-serif; font-size: 0.78em; letter-spacing: 0.04em; text-transform: uppercase; margin: 0 0 2em; }
        h1, h2, h3, h4, h5, h6 { font-family: \(t.heading); font-weight: \(t.headingWeight); line-height: 1.22; }
        h1 { font-size: 2.3em; margin: 0 0 0.5em; }
        h2 { font-size: 1.5em; margin: 1.9em 0 0.6em; }
        h3 { font-size: 1.2em; margin: 1.6em 0 0.5em; }
        p, ul, ol, pre, blockquote { margin: 0 0 1.25em; }
        li { margin: 0.3em 0; }
        a { text-decoration-thickness: 1px; text-underline-offset: 3px; }
        blockquote { margin-left: 0; padding: 0.1em 0 0.1em 1.1em; border-left: 3px solid; font-style: italic; }
        code { font-family: "SF Mono", ui-monospace, Menlo, monospace; font-size: 0.86em; padding: 0.12em 0.35em; border-radius: 5px; }
        pre { padding: 1em 1.2em; border-radius: 10px; overflow-x: auto; }
        pre code { background: none; padding: 0; }
        img, video { display: block; max-width: 100%; height: auto; border-radius: 10px; margin: 1.8em auto; }
        mark { color: inherit; padding: 0 0.15em; border-radius: 3px; }
        hr { border: none; text-align: center; margin: 2.6em 0; }
        hr::after { content: "⁂"; letter-spacing: 0.5em; }
        .embed { display: block; position: relative; aspect-ratio: 16 / 9; margin: 1.8em 0; }
        .embed iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; border-radius: 10px; }
        input[type=checkbox] { margin-right: 0.4em; }
        \(t.extra)
        """
        if print { return base + colors(light) }
        return base + colors(light) + "\n@media (prefers-color-scheme: dark) {\n" + colors(dark) + "\n}"
    }
}

/// Turns a sheet into the body of a blog post: a header from front matter
/// (title, date, reading time) followed by the rendered Markdown.
enum BlogRenderer {
    static func body(markdown: String) -> String {
        let fields = FrontMatter.fields(markdown)
        let content = MarkdownHTML.convert(markdown)
        let minutes = max(1, Int((Double(TextStats.contentWords(markdown)) / 238).rounded()))
        var meta = ["\(minutes) min read"]
        if let date = fields["date"].flatMap(formatDate) { meta.insert(date, at: 0) }
        let metaHTML = "<p class=\"meta\">\(MarkdownHTML.escape(meta.joined(separator: " · ")))</p>"

        if let title = fields["title"], !title.isEmpty {
            return "<header class=\"post-header\"><h1>\(MarkdownHTML.escape(title))</h1>\(metaHTML)</header>\n" + content
        }
        // No front matter title: let the first heading lead, with the meta line beneath it.
        if content.hasPrefix("<h1>"), let end = content.range(of: "</h1>") {
            return "<header class=\"post-header\">" + content[..<end.upperBound] + metaHTML + "</header>" + content[end.upperBound...]
        }
        return content
    }

    private static func formatDate(_ value: String) -> String? {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(value.prefix(10))) else { return nil }
        return date.formatted(date: .long, time: .omitted)
    }
}
