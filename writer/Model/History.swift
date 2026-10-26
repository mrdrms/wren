import CryptoKit
import Foundation

/// Stable per-document storage key, so history follows a sheet without touching its folder.
enum DocumentKey {
    static func make(_ document: URL) -> String {
        let digest = SHA256.hash(data: Data(document.standardizedFileURL.path.utf8))
        return digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    static func supportFolder(_ name: String) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = support.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// One step in a document's life: at `loc` (UTF-16), `old` was replaced by `new`.
/// Storing both sides makes the history playable in either direction.
struct TextChange: Codable, Equatable {
    var t: Date
    var loc: Int
    var old: String
    var new: String

    /// The single contiguous edit that turns `a` into `b` (common prefix/suffix trimmed).
    static func between(_ a: String, _ b: String, at date: Date = .now) -> TextChange? {
        let x = a as NSString, y = b as NSString
        if x.isEqual(to: b) { return nil }
        let shortest = min(x.length, y.length)
        var prefix = 0
        while prefix < shortest && x.character(at: prefix) == y.character(at: prefix) { prefix += 1 }
        // Never split a surrogate pair.
        if prefix > 0, (0xD800...0xDBFF).contains(x.character(at: prefix - 1)) { prefix -= 1 }
        var suffix = 0
        while suffix < shortest - prefix && x.character(at: x.length - 1 - suffix) == y.character(at: y.length - 1 - suffix) { suffix += 1 }
        if suffix > 0, (0xDC00...0xDFFF).contains(x.character(at: x.length - suffix)) { suffix -= 1 }
        return TextChange(t: date, loc: prefix,
                          old: x.substring(with: NSRange(location: prefix, length: x.length - prefix - suffix)),
                          new: y.substring(with: NSRange(location: prefix, length: y.length - prefix - suffix)))
    }

    func apply(to s: NSMutableString) {
        s.replaceCharacters(in: NSRange(location: loc, length: (old as NSString).length), with: new)
    }

    func revert(on s: NSMutableString) {
        s.replaceCharacters(in: NSRange(location: loc, length: (new as NSString).length), with: old)
    }

    var insertedRange: NSRange { NSRange(location: loc, length: (new as NSString).length) }
}

/// Every pause in your typing, recorded as an append-only log per sheet.
enum HistoryStore {
    private static var folder: URL { DocumentKey.supportFolder("History") }

    private static func url(for document: URL) -> URL {
        folder.appendingPathComponent(DocumentKey.make(document)).appendingPathExtension("jsonl")
    }

    static func load(for document: URL) -> [TextChange] {
        guard let data = try? Data(contentsOf: url(for: document)) else { return [] }
        let decoder = JSONDecoder()
        return data.split(separator: UInt8(ascii: "\n")).compactMap { try? decoder.decode(TextChange.self, from: $0) }
    }

    /// Text at the end of the recorded history.
    static func replay(_ changes: [TextChange]) -> String {
        let s = NSMutableString()
        for change in changes where change.loc + (change.old as NSString).length <= s.length {
            change.apply(to: s)
        }
        return s as String
    }

    static func append(_ change: TextChange, for document: URL) {
        guard var line = try? JSONEncoder().encode(change) else { return }
        line.append(UInt8(ascii: "\n"))
        let file = url(for: document)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        } else {
            try? line.write(to: file)
        }
    }

    /// The sheet's record follows it; anything left at the destination by an older file
    /// of the same name is stale and gives way.
    static func move(from old: URL, to new: URL) {
        let source = url(for: old), target = url(for: new)
        guard source != target, FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: source, to: target)
    }
}

/// A passage you deleted, kept in case you want it back.
struct Cut: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    var text: String
}

/// The Cutting Room Floor: large deletions are saved automatically, per sheet.
enum CuttingRoom {
    private static var folder: URL { DocumentKey.supportFolder("CuttingRoom") }

    private static func url(for document: URL) -> URL {
        folder.appendingPathComponent(DocumentKey.make(document)).appendingPathExtension("json")
    }

    static func load(for document: URL) -> [Cut] {
        guard let data = try? Data(contentsOf: url(for: document)) else { return [] }
        return (try? JSONDecoder().decode([Cut].self, from: data)) ?? []
    }

    static func save(_ cuts: [Cut], for document: URL) {
        if let data = try? JSONEncoder().encode(Array(cuts.prefix(300))) {
            try? data.write(to: url(for: document), options: .atomic)
        }
    }

    /// The sheet's record follows it; anything left at the destination by an older file
    /// of the same name is stale and gives way.
    static func move(from old: URL, to new: URL) {
        let source = url(for: old), target = url(for: new)
        guard source != target, FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.moveItem(at: source, to: target)
    }
}
