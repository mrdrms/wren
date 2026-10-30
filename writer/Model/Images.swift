import AppKit
import AVFoundation
import Foundation
import UniformTypeIdentifiers

enum ImageSource {
    case file(URL)
    case data(Data, ext: String)
}

enum MediaKind: Equatable {
    case image
    case video
    case youtube(id: String)
}

/// Markdown image syntax helpers. Videos use the same `![caption](clip.mp4)` form.
nonisolated enum MarkdownImage {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "webm"]

    static func kind(of path: String) -> MediaKind {
        if let id = youTubeID(path) { return .youtube(id: id) }
        let ext = (path.components(separatedBy: "?").first.map { ($0 as NSString).pathExtension } ?? "").lowercased()
        return videoExtensions.contains(ext) ? .video : .image
    }

    /// Video ID from youtube.com/watch?v=, youtu.be/, /shorts/ or /embed/ links.
    static func youTubeID(_ string: String) -> String? {
        guard let url = URL(string: string.replacingOccurrences(of: "&amp;", with: "&")), let host = url.host?.lowercased() else { return nil }
        var id: String?
        if host.hasSuffix("youtu.be") {
            id = url.pathComponents.dropFirst().first
        } else if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            let parts = url.pathComponents
            if let index = parts.firstIndex(where: { $0 == "shorts" || $0 == "embed" || $0 == "live" }), index + 1 < parts.count {
                id = parts[index + 1]
            } else {
                id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
            }
        }
        guard let id, id.count >= 6, id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return id
    }

    /// An image on a line of its own: `![alt](path "optional title")`.
    static let lineRegex = try! NSRegularExpression(pattern: "^[ \\t]*!\\[([^\\]\\n]*)\\]\\(([^)\\s]+)(?:[ \\t]+\"[^\"\\n]*\")?\\)[ \\t]*$", options: .anchorsMatchLines)
    static let anyRegex = try! NSRegularExpression(pattern: "!\\[([^\\]\\n]*)\\]\\(([^)\\s]+)(?:[ \\t]+\"[^\"\\n]*\")?\\)")

    /// Resolves an image reference against the sheet's folder. Remote URLs pass through.
    static func resolve(_ path: String, relativeTo folder: URL?) -> URL? {
        if let url = URL(string: path), let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) {
            return url
        }
        guard let folder else { return nil }
        let decoded = path.removingPercentEncoding ?? path
        if decoded.hasPrefix("/") { return URL(fileURLWithPath: decoded) }
        return folder.appendingPathComponent(decoded).standardizedFileURL
    }

    static func references(in text: String) -> [(range: NSRange, alt: String, path: String)] {
        let ns = text as NSString
        return anyRegex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map {
            ($0.range, ns.substring(with: $0.range(at: 1)), ns.substring(with: $0.range(at: 2)))
        }
    }

    // MARK: Sizes

    /// A width written at the end of the alt text, the way Obsidian does it:
    /// `![Sketch|60%](…)` is 60% of the column, `![Sketch|300](…)` is 300 points.
    /// Apps that don't know the convention simply show the picture at its usual size.
    enum Width: Equatable {
        case percent(Int)
        case points(Int)

        /// How wide this is in a column of the given width.
        func resolved(in column: Double) -> Double {
            switch self {
            case .percent(let p): column * Double(p) / 100
            case .points(let p): min(column, Double(p))
            }
        }
    }

    private static let sizeSuffix = try! NSRegularExpression(pattern: #"^(.*?)\|\s*(\d{1,4})\s*(%?)\s*$"#, options: .dotMatchesLineSeparators)

    /// The caption and the width, from alt text that may end in `|60%` or `|300`.
    static func split(alt: String) -> (caption: String, width: Width?) {
        let ns = alt as NSString
        guard let m = sizeSuffix.firstMatch(in: alt, range: NSRange(location: 0, length: ns.length)),
              let number = Int(ns.substring(with: m.range(at: 2))), number > 0 else { return (alt, nil) }
        let caption = ns.substring(with: m.range(at: 1))
        if m.range(at: 3).length > 0 { return (caption, .percent(min(100, max(5, number)))) }
        return (caption, .points(number))
    }

    /// Alt text carrying a width (or none, to go back to the natural size).
    static func alt(caption: String, width: Width?) -> String {
        switch width {
        case .percent(let p): "\(caption)|\(p)%"
        case .points(let p): "\(caption)|\(p)"
        case nil: caption
        }
    }

    /// The same Markdown with every size marker removed, for places that take raw Markdown
    /// and wouldn't understand it.
    static func withoutSizes(_ text: String) -> String {
        guard text.contains("![") else { return text }
        let result = NSMutableString(string: text)
        for m in anyRegex.matches(in: text, range: NSRange(location: 0, length: result.length)).reversed() {
            let alt = result.substring(with: m.range(at: 1))
            let (caption, width) = split(alt: alt)
            if width != nil { result.replaceCharacters(in: m.range(at: 1), with: caption) }
        }
        return result as String
    }

    /// Image markup removed, so alt text and file names don't count as words.
    static func stripForCounting(_ text: String) -> String {
        guard text.contains("![") else { return text }
        return anyRegex.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: (text as NSString).length), withTemplate: "")
    }
}

/// YAML front matter (`---` … `---` at the very top), the metadata block static-site generators use.
nonisolated enum FrontMatter {
    static func range(in text: String) -> NSRange? {
        guard text.hasPrefix("---\n") || text.hasPrefix("---\r\n") else { return nil }
        let ns = text as NSString
        let closing = ns.range(of: "\n---", options: [], range: NSRange(location: 3, length: ns.length - 3))
        guard closing.location != NSNotFound else { return nil }
        var end = NSMaxRange(closing)
        // The closing fence must be a whole line.
        if end < ns.length {
            guard ns.character(at: end) == 10 || ns.character(at: end) == 13 else { return nil }
            end += 1
        }
        // A sheet that merely opens with a divider isn't metadata: every line between the
        // fences has to look like YAML (`key: value`, list items, indented values, comments).
        let inner = ns.substring(with: NSRange(location: 3, length: closing.location - 3))
        let lines = inner.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !lines.isEmpty, lines.allSatisfy({ line in
            line.first?.isWhitespace == true || line.hasPrefix("- ") || line.hasPrefix("#")
                || line.range(of: #"^[A-Za-z0-9_][\w .-]*:(\s|$)"#, options: .regularExpression) != nil
        }) else { return nil }
        return NSRange(location: 0, length: end)
    }

    static func strip(_ text: String) -> String {
        guard let range = range(in: text) else { return text }
        return (text as NSString).substring(from: NSMaxRange(range))
    }

    /// Simple `key: value` pairs from the front matter (quotes removed).
    static func fields(_ text: String) -> [String: String] {
        guard let range = range(in: text) else { return [:] }
        var fields: [String: String] = [:]
        for line in (text as NSString).substring(with: range).split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":"), line != "---" else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast()).replacingOccurrences(of: "\\\"", with: "\"")
            }
            if !key.isEmpty { fields[key] = value }
        }
        return fields
    }

    static func make(title: String, date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let escaped = title.replacingOccurrences(of: "\"", with: "\\\"")
        return "---\ntitle: \"\(escaped)\"\ndate: \(formatter.string(from: date))\ndraft: false\n---\n\n"
    }
}

/// Copies images into an `assets` folder beside the sheet, so posts and their pictures travel together.
enum ImageImporter {
    static let folderName = "assets"
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "svg", "avif", "bmp"]
    static var mediaExtensions: Set<String> { imageExtensions.union(MarkdownImage.videoExtensions) }

    static func importImage(_ source: ImageSource, for document: URL) throws -> (path: String, alt: String) {
        let folder = document.deletingLastPathComponent().appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        switch source {
        case .file(let url):
            let base = slug(url.deletingPathExtension().lastPathComponent)
            let target = unique(in: folder, base: base.isEmpty ? "image" : base, ext: url.pathExtension.lowercased())
            // Already in this sheet's assets folder? Just link to it.
            if url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL {
                return ("\(folderName)/\(url.lastPathComponent)", alt(from: url))
            }
            try FileManager.default.copyItem(at: url, to: target)
            return ("\(folderName)/\(target.lastPathComponent)", alt(from: url))
        case .data(let data, let ext):
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let target = unique(in: folder, base: "image-\(formatter.string(from: .now))", ext: ext)
            try data.write(to: target)
            return ("\(folderName)/\(target.lastPathComponent)", "")
        }
    }

    /// Pasted screenshots usually arrive as TIFF; blogs want PNG.
    static func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) { return png }
        guard let tiff = pasteboard.data(forType: .tiff), let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    static func mediaFileURLs(on pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { mediaExtensions.contains($0.pathExtension.lowercased()) }
    }

    static func slug(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let dashed = name.lowercased().unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        return String(String(dashed).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-").prefix(60))
    }

    private static func alt(from url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
    }

    private static func unique(in folder: URL, base: String, ext: String) -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base)-\(n)").appendingPathExtension(ext)
            n += 1
        }
        return candidate
    }
}

/// Loads preview images once (local files immediately, web images in the background),
/// and measures videos so the editor can reserve the right amount of room.
final class ImagePreviewCache {
    static let shared = ImagePreviewCache()

    private var images: [URL: NSImage] = [:]
    private var videoSizes: [URL: NSSize] = [:]
    private var measuring: Set<URL> = []

    func videoSize(for url: URL, onLoad: @escaping () -> Void) -> NSSize? {
        if let size = videoSizes[url] { return size }
        guard !measuring.contains(url), !failed.contains(url) else { return nil }
        measuring.insert(url)
        Task {
            let asset = AVURLAsset(url: url)
            var size: NSSize?
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let (natural, transform) = try? await track.load(.naturalSize, .preferredTransform) {
                let rect = CGRect(origin: .zero, size: natural).applying(transform)
                size = NSSize(width: abs(rect.width), height: abs(rect.height))
            }
            measuring.remove(url)
            if let size, size.width > 0 {
                videoSizes[url] = size
                onLoad()
            } else {
                failed.insert(url)
            }
        }
        return nil
    }
    private var failed: Set<URL> = []
    private var loading: Set<URL> = []

    func image(for url: URL, onLoad: @escaping () -> Void) -> NSImage? {
        if let image = images[url] { return image }
        guard !failed.contains(url), !loading.contains(url) else { return nil }
        if url.isFileURL {
            if let image = NSImage(contentsOf: url), image.size.width > 0 {
                images[url] = image
                return image
            }
            failed.insert(url)
            return nil
        }
        loading.insert(url)
        Task {
            let data = try? await URLSession.shared.data(from: url).0
            loading.remove(url)
            if let data, let image = NSImage(data: data), image.size.width > 0 {
                images[url] = image
                onLoad()
            } else {
                failed.insert(url)
            }
        }
        return nil
    }

    /// Forget a file so a replaced image shows up fresh.
    func invalidate(_ url: URL) {
        images[url] = nil
        failed.remove(url)
    }
}
