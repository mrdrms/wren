import Foundation

struct Snapshot: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let date: Date
    let words: Int
    let preview: String
}

/// Point-in-time copies of a sheet, kept outside your writing folders so they never clutter them.
enum SnapshotStore {
    private static let root: URL = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Snapshots", isDirectory: true)
    }()

    private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func folder(for document: URL) -> URL {
        root.appendingPathComponent(DocumentKey.make(document), isDirectory: true)
    }

    @discardableResult
    static func take(of document: URL, text: String) throws -> Snapshot {
        let folder = folder(for: document)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let date = Date.now
        let name = formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
        let url = folder.appendingPathComponent(name).appendingPathExtension("md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return Snapshot(url: url, date: date, words: TextStats.contentWords(text), preview: String(text.prefix(200)))
    }

    static func list(for document: URL) -> [Snapshot] {
        let folder = folder(for: document)
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return files.compactMap { url -> Snapshot? in
            guard url.pathExtension == "md", let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            return Snapshot(url: url, date: date, words: TextStats.contentWords(text), preview: String(text.prefix(200)))
        }
        .sorted { $0.date > $1.date }
    }

    static func text(of snapshot: Snapshot) -> String {
        (try? String(contentsOf: snapshot.url, encoding: .utf8)) ?? ""
    }

    static func delete(_ snapshot: Snapshot) {
        try? FileManager.default.removeItem(at: snapshot.url)
    }

    /// Keeps snapshots attached to a sheet after it's renamed, merging with any already there.
    static func move(from old: URL, to new: URL) {
        let fm = FileManager.default
        let source = folder(for: old)
        let target = folder(for: new)
        guard source != target, fm.fileExists(atPath: source.path) else { return }
        guard fm.fileExists(atPath: target.path) else {
            try? fm.moveItem(at: source, to: target)
            return
        }
        for file in (try? fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)) ?? [] {
            try? fm.moveItem(at: file, to: target.appendingPathComponent(file.lastPathComponent))
        }
        try? fm.removeItem(at: source)
    }
}
