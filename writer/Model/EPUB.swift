import Foundation
import UniformTypeIdentifiers

/// A minimal ZIP writer: entries are stored uncompressed, which EPUB readers accept and
/// which keeps this small enough to trust.
struct ZipWriter {
    private var data = Data()
    private var central = Data()
    private var count: UInt16 = 0

    mutating func add(_ path: String, _ content: Data) {
        let name = Data(path.utf8)
        let crc = CRC32.checksum(content)
        let offset = UInt32(data.count)
        // Local file header
        data.append(le32(0x0403_4B50)); data.append(le16(20)); data.append(le16(0x0800)); data.append(le16(0))
        data.append(le16(0)); data.append(le16(0x21)) // time, date (1980-01-01)
        data.append(le32(crc)); data.append(le32(UInt32(content.count))); data.append(le32(UInt32(content.count)))
        data.append(le16(UInt16(name.count))); data.append(le16(0))
        data.append(name); data.append(content)
        // Central directory record
        central.append(le32(0x0201_4B50)); central.append(le16(20)); central.append(le16(20)); central.append(le16(0x0800)); central.append(le16(0))
        central.append(le16(0)); central.append(le16(0x21))
        central.append(le32(crc)); central.append(le32(UInt32(content.count))); central.append(le32(UInt32(content.count)))
        central.append(le16(UInt16(name.count))); central.append(le16(0)); central.append(le16(0)); central.append(le16(0)); central.append(le16(0))
        central.append(le32(0)); central.append(le32(offset)); central.append(name)
        count += 1
    }

    func finish() -> Data {
        var result = data
        let start = UInt32(result.count)
        result.append(central)
        result.append(le32(0x0605_4B50)); result.append(le16(0)); result.append(le16(0))
        result.append(le16(count)); result.append(le16(count))
        result.append(le32(UInt32(central.count))); result.append(le32(start)); result.append(le16(0))
        return result
    }

    private func le16(_ value: UInt16) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
    private func le32(_ value: UInt32) -> Data { withUnsafeBytes(of: value.littleEndian) { Data($0) } }
}

enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }
}

/// An EPUB 3 ebook for Apple Books, Kobo and Kindle (via Send to Kindle): a title page,
/// one page per chapter, a table of contents, and the book's images inside it.
enum EPUBBuilder {
    static func build(title: String, author: String?, chapters: [String], titlePage: Bool, folder: URL) -> Data {
        var zip = ZipWriter()
        // The mimetype must come first, uncompressed: that's how readers recognise an EPUB.
        zip.add("mimetype", Data("application/epub+zip".utf8))
        zip.add("META-INF/container.xml", Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
        </container>
        """.utf8))
        zip.add("OEBPS/style.css", Data(css.utf8))

        var manifest: [(id: String, href: String, type: String)] = [("css", "style.css", "text/css")]
        var spine: [String] = []
        var toc: [(href: String, title: String)] = []
        var images: [URL: String] = [:]

        if titlePage {
            let byline = author.map { "<p class=\"author\">\(MarkdownHTML.escape($0))</p>" } ?? ""
            zip.add("OEBPS/title.xhtml", Data(page(title: title, body: "<section class=\"title-page\"><h1>\(MarkdownHTML.escape(title))</h1>\(byline)</section>").utf8))
            manifest.append(("title", "title.xhtml", "application/xhtml+xml"))
            spine.append("title")
        }
        for (index, markdown) in chapters.enumerated() {
            let id = String(format: "ch%03d", index + 1)
            MarkdownHTML.videosAsLinks = true
            var body = xhtml(MarkdownHTML.convert(markdown))
            MarkdownHTML.videosAsLinks = false
            body = packImages(in: body, folder: folder, images: &images, zip: &zip, manifest: &manifest)
            let heading = Heading.parse(markdown).first?.title ?? "Chapter \(index + 1)"
            zip.add("OEBPS/\(id).xhtml", Data(page(title: heading, body: "<section class=\"chapter\">\n\(body)\n</section>").utf8))
            manifest.append((id, "\(id).xhtml", "application/xhtml+xml"))
            spine.append(id)
            toc.append(("\(id).xhtml", heading))
        }

        let nav = toc.map { "<li><a href=\"\($0.href)\">\(MarkdownHTML.escape($0.title))</a></li>" }.joined(separator: "\n")
        zip.add("OEBPS/nav.xhtml", Data(page(title: "Contents", body: "<nav epub:type=\"toc\" id=\"toc\"><h1>Contents</h1><ol>\n\(nav)\n</ol></nav>").utf8))

        let modified = ISO8601DateFormatter().string(from: .now).replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        let items = manifest.map { "<item id=\"\($0.id)\" href=\"\($0.href)\" media-type=\"\($0.type)\"/>" }.joined(separator: "\n    ")
        let opf = """
        <?xml version="1.0" encoding="UTF-8"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid" xml:lang="en">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:identifier id="bookid">urn:uuid:\(UUID().uuidString.lowercased())</dc:identifier>
            <dc:title>\(MarkdownHTML.escape(title))</dc:title>
            \(author.map { "<dc:creator>\(MarkdownHTML.escape($0))</dc:creator>" } ?? "")
            <dc:language>\(Locale.current.language.languageCode?.identifier ?? "en")</dc:language>
            <meta property="dcterms:modified">\(modified)</meta>
          </metadata>
          <manifest>
            <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
            \(items)
          </manifest>
          <spine>
            \(spine.map { "<itemref idref=\"\($0)\"/>" }.joined(separator: "\n    "))
          </spine>
        </package>
        """
        zip.add("OEBPS/content.opf", Data(opf.utf8))
        return zip.finish()
    }

    private static func page(title: String, body: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE html>
        <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
        <head><meta charset="UTF-8"/><title>\(MarkdownHTML.escape(title))</title><link rel="stylesheet" type="text/css" href="style.css"/></head>
        <body>
        \(body)
        </body>
        </html>
        """
    }

    /// EPUB pages are XML: void elements close themselves, and checkboxes become symbols.
    static func xhtml(_ html: String) -> String {
        var result = html
            .replacingOccurrences(of: #"<input type="checkbox" disabled checked>"#, with: "☑")
            .replacingOccurrences(of: #"<input type="checkbox" disabled>"#, with: "☐")
        result = result.replacingOccurrences(of: #"<(hr|br|img)((?:\s[^>]*?)?)\s*/?>"#, with: "<$1$2/>", options: .regularExpression)
        return result
    }

    /// Copies each local image into the book and points the page at the copy.
    private static func packImages(in body: String, folder: URL, images: inout [URL: String], zip: inout ZipWriter,
                                   manifest: inout [(id: String, href: String, type: String)]) -> String {
        let regex = try! NSRegularExpression(pattern: #"<img ([^>]*?)src="([^"]+)""#)
        let result = NSMutableString(string: body)
        for match in regex.matches(in: body, range: NSRange(location: 0, length: result.length)).reversed() {
            let src = result.substring(with: match.range(at: 2)).replacingOccurrences(of: "&amp;", with: "&")
            guard let file = MarkdownImage.resolve(src, relativeTo: folder), file.isFileURL else { continue }
            var href = images[file]
            if href == nil, let data = try? Data(contentsOf: file) {
                let name = "images/img\(images.count + 1).\(file.pathExtension.lowercased())"
                zip.add("OEBPS/\(name)", data)
                let type = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "image/png"
                manifest.append(("img\(images.count + 1)", name, type))
                images[file] = name
                href = name
            }
            if let href { result.replaceCharacters(in: match.range(at: 2), with: href) }
        }
        return result as String
    }

    private static let css = """
    body { font-family: Georgia, "Iowan Old Style", serif; line-height: 1.5; margin: 0 5%; }
    p { margin: 0; text-indent: 1.5em; text-align: justify; hyphens: auto; -webkit-hyphens: auto; }
    h1 + p, h2 + p, h3 + p, hr + p, blockquote + p, .chapter > p:first-child { text-indent: 0; }
    h1 { text-align: center; font-weight: normal; font-size: 1.8em; margin: 2.5em 0 1.5em; }
    h2, h3 { text-align: center; font-size: 1.15em; margin: 1.6em 0 0.8em; }
    hr { border: none; text-align: center; margin: 1.2em 0; }
    hr::after { content: "⁂"; }
    blockquote { margin: 1em 1.5em; font-style: italic; }
    img { max-width: 100%; height: auto; display: block; margin: 1em auto; }
    pre, code { font-family: Menlo, monospace; font-size: 0.85em; }
    pre { white-space: pre-wrap; margin: 1em 0; }
    .title-page { text-align: center; margin-top: 30%; }
    .title-page h1 { font-size: 2.4em; margin: 0 0 1em; }
    .author { text-indent: 0; text-align: center; font-style: italic; font-size: 1.2em; }
    .footnotes { font-size: 0.85em; margin-top: 2em; }
    .footnotes p, .footnotes li { text-indent: 0; }
    sup { font-size: 0.7em; line-height: 0; }
    """
}
