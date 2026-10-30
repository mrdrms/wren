import AppKit
import Foundation
import Observation

struct Sheet: Identifiable, Hashable {
    var id: URL { url }
    var url: URL
    var folder: URL
    var title: String
    var preview: String
    var modified: Date
    var words: Int
    var searchText: String
}

struct FolderNode: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let isRoot: Bool
    var kind: ProjectKind? = nil
    var children: [FolderNode]?
}

enum SidebarSelection: Hashable {
    case all, recent, folder(URL)
}

enum NavigatorPage {
    case library, sheets
}

/// Your writing lives as plain Markdown files in ordinary folders: no proprietary
/// database, no lock-in. Wren keeps a default library and can add any folder you choose.
@Observable
final class LibraryStore {
    static let markdownExtensions: Set<String> = ["md", "markdown", "txt", "text"]

    private(set) var roots: [URL] = []
    private(set) var tree: [FolderNode] = []
    private(set) var sheets: [Sheet] = []
    /// Folders that are projects (book, blog, journal), keyed by folder URL.
    private(set) var projects: [URL: ProjectInfo] = [:]

    @ObservationIgnored private let fm = FileManager.default
    @ObservationIgnored private let defaults = UserDefaults.standard

    let defaultRoot: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Wren Library", isDirectory: true)
    }()

    init() {
        let isFirstLaunch = !fm.fileExists(atPath: defaultRoot.path)
        try? fm.createDirectory(at: defaultRoot, withIntermediateDirectories: true)
        if isFirstLaunch { seedWelcomeContent() }
        if defaults.integer(forKey: "seedVersion") < 2 {
            let whatsNew = defaultRoot.appendingPathComponent("New in Wren.md")
            if !fm.fileExists(atPath: whatsNew.path) {
                try? WelcomeContent.whatsNew.write(to: whatsNew, atomically: true, encoding: .utf8)
            }
            defaults.set(2, forKey: "seedVersion")
        }
        roots = [defaultRoot] + resolveBookmarks()
        refresh()
    }

    func isUserAdded(_ url: URL) -> Bool {
        url != defaultRoot && roots.contains(url)
    }

    // MARK: Scanning

    func refresh() {
        var allSheets: [Sheet] = []
        var foundProjects: [URL: ProjectInfo] = [:]
        tree = roots.map { root in
            var node = scanFolder(root, isRoot: true, into: &allSheets, projects: &foundProjects)
            if root == defaultRoot { node = FolderNode(url: node.url, name: "My Writing", isRoot: true, kind: node.kind, children: node.children) }
            return node
        }
        projects = foundProjects
        sheets = allSheets.sorted { $0.modified > $1.modified }
    }

    private func scanFolder(_ folder: URL, isRoot: Bool, into sheets: inout [Sheet], projects: inout [URL: ProjectInfo]) -> FolderNode {
        let project = ProjectInfo.load(from: folder)
        if let project { projects[folder] = project }
        let contents = (try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])) ?? []
        var children: [FolderNode] = []
        for url in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey])
            if values?.isDirectory == true {
                // Media folders belong to their sheets, not the sidebar.
                if url.lastPathComponent == ImageImporter.folderName { continue }
                children.append(scanFolder(url, isRoot: false, into: &sheets, projects: &projects))
            } else if Self.markdownExtensions.contains(url.pathExtension.lowercased()) {
                let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                sheets.append(makeSheet(url: url, folder: folder, text: text, modified: values?.contentModificationDate ?? .now))
            }
        }
        return FolderNode(url: folder, name: folder.lastPathComponent, isRoot: isRoot, kind: project?.kind, children: children.isEmpty ? nil : children)
    }

    private func makeSheet(url: URL, folder: URL, text: String, modified: Date) -> Sheet {
        let (title, preview) = Self.titleAndPreview(text: text, fallback: url.deletingPathExtension().lastPathComponent)
        return Sheet(url: url, folder: folder, title: title, preview: preview, modified: modified,
                     words: TextStats.contentWords(text), searchText: String(text.prefix(8000)).lowercased())
    }

    /// The title and a short preview, from the text readers will see: no Markdown symbols,
    /// guidance notes or images. A front matter title wins, since that's what a blog shows.
    static func titleAndPreview(text: String, fallback: String) -> (String, String) {
        var lines = MarkdownText.plain(text).split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var title = lines.isEmpty ? fallback : lines.removeFirst()
        if let front = FrontMatter.fields(text)["title"], !front.isEmpty { title = front }
        let preview = lines.prefix(4).joined(separator: " ")
        return (title.isEmpty ? fallback : title, String(preview.prefix(160)))
    }

    /// Cheap in-place refresh after a save, without rescanning the disk.
    func updateSheet(at url: URL, text: String) {
        guard let index = sheets.firstIndex(where: { $0.url == url }) else { return }
        sheets[index] = makeSheet(url: url, folder: sheets[index].folder, text: text, modified: .now)
    }

    func sheets(for selection: SidebarSelection?, search: String) -> [Sheet] {
        var result: [Sheet]
        switch selection {
        case .folder(let folder):
            result = sheets.filter { $0.folder == folder }
            if projects[folder]?.kind == .book {
                // Books read in chapter order, not by last edit.
                result.sort { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
            } else if projects[folder]?.kind == .journal {
                result.sort { $0.url.lastPathComponent > $1.url.lastPathComponent }
            }
        case .recent:
            let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
            result = sheets.filter { $0.modified >= cutoff }
        case .all, nil:
            result = sheets
        }
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter { $0.title.lowercased().contains(query) || $0.searchText.contains(query) }
        }
        return result
    }

    // MARK: File operations

    func createSheet(in folder: URL, named name: String = "Untitled", text: String = "") throws -> URL {
        let base = Self.sanitize(name)
        let url = uniqueURL(in: folder, base: base.isEmpty ? "Untitled" : base, ext: "md")
        try text.write(to: url, atomically: true, encoding: .utf8)
        refresh()
        return url
    }

    func createFolder(in parent: URL, name: String) throws -> URL {
        let url = uniqueURL(in: parent, base: Self.sanitize(name).isEmpty ? "New Folder" : Self.sanitize(name), ext: nil)
        try fm.createDirectory(at: url, withIntermediateDirectories: false)
        refresh()
        return url
    }

    func rename(_ url: URL, to newName: String) throws -> URL {
        let clean = Self.sanitize(newName)
        guard !clean.isEmpty else { return url }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        let ext = isDirectory ? nil : (url.pathExtension.isEmpty ? "md" : url.pathExtension)
        let current = isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        guard clean != current else { return url }
        // Only the capitalization changes: the file system sees the same name, so don't let
        // uniqueURL turn it into "Name 2".
        let target = clean.lowercased() == current.lowercased()
            ? url.deletingLastPathComponent().appendingPathComponent(ext.map { "\(clean).\($0)" } ?? clean, isDirectory: isDirectory)
            : uniqueURL(in: url.deletingLastPathComponent(), base: clean, ext: ext)
        try fm.moveItem(at: url, to: target)
        refresh()
        return target
    }

    func duplicate(_ url: URL) throws -> URL {
        let base = url.deletingPathExtension().lastPathComponent + " copy"
        let target = uniqueURL(in: url.deletingLastPathComponent(), base: base, ext: url.pathExtension)
        try fm.copyItem(at: url, to: target)
        refresh()
        return target
    }

    /// Returns where the item landed in the Trash.
    @discardableResult
    func trash(_ url: URL) throws -> URL? {
        var resulting: NSURL?
        try fm.trashItem(at: url, resultingItemURL: &resulting)
        refresh()
        return resulting as URL?
    }

    func move(_ url: URL, to folder: URL) throws -> URL {
        // Dropped where it already is: nothing to do (and no "Name 2" copy of its name).
        guard url.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL else { return url }
        let target = uniqueURL(in: folder, base: url.deletingPathExtension().lastPathComponent, ext: url.pathExtension)
        try fm.moveItem(at: url, to: target)
        bringMedia(of: target, from: url.deletingLastPathComponent())
        refresh()
        return target
    }

    /// Images and videos are linked relative to the sheet (`assets/photo.png`). After a move,
    /// copy the ones it uses so its links keep working. Copied, not moved: other sheets in
    /// the old folder may use them too.
    private func bringMedia(of sheet: URL, from oldFolder: URL) {
        guard Self.markdownExtensions.contains(sheet.pathExtension.lowercased()),
              let text = try? String(contentsOf: sheet, encoding: .utf8) else { return }
        let newFolder = sheet.deletingLastPathComponent()
        for reference in MarkdownImage.references(in: text) {
            let path = reference.path.removingPercentEncoding ?? reference.path
            guard URL(string: reference.path)?.scheme == nil, !path.hasPrefix("/"), !path.contains("..") else { continue }
            let source = oldFolder.appendingPathComponent(path)
            let destination = newFolder.appendingPathComponent(path)
            guard Safety.isMediaFile(source), !fm.fileExists(atPath: destination.path) else { continue }
            try? fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.copyItem(at: source, to: destination)
            // A drawing's strokes travel with its picture, so it stays editable.
            let strokes = DrawingFiles.sidecar(for: source)
            if fm.fileExists(atPath: strokes.path) {
                try? fm.copyItem(at: strokes, to: DrawingFiles.sidecar(for: destination))
            }
        }
    }

    private func uniqueURL(in folder: URL, base: String, ext: String?) -> URL {
        func make(_ name: String) -> URL {
            let url = folder.appendingPathComponent(name, isDirectory: ext == nil)
            return ext.map { url.appendingPathExtension($0) } ?? url
        }
        var candidate = make(base)
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = make("\(base) \(n)")
            n += 1
        }
        return candidate
    }

    static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\?%*|\"<>\n\r\t")
        let cleaned = name.components(separatedBy: illegal).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        return String(cleaned.prefix(80))
    }

    // MARK: Projects

    func createProject(_ template: ProjectTemplate, name: String, author: String?, goal: Int?, in parent: URL) throws -> URL {
        let folder = uniqueURL(in: parent, base: Self.sanitize(name).isEmpty ? template.name : Self.sanitize(name), ext: nil)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try ProjectInfo(kind: template.kind, goal: goal, author: author).save(to: folder)
        for file in template.files {
            let url = folder.appendingPathComponent(file.path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Templates.render(file.body, title: name).write(to: url, atomically: true, encoding: .utf8)
        }
        refresh()
        return folder
    }

    func setProject(_ info: ProjectInfo?, for folder: URL) {
        if let info {
            try? info.save(to: folder)
        } else {
            try? fm.removeItem(at: folder.appendingPathComponent(ProjectInfo.fileName))
        }
        refresh()
    }

    /// Chapters of a book: the Markdown files directly inside it, in file-name order.
    func chapters(in folder: URL) -> [Sheet] {
        sheets.filter { $0.folder == folder }
            .sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
    }

    func createChapter(in folder: URL) throws -> URL {
        let next = (chapters(in: folder).compactMap { Chapters.number(of: $0.url) }.max() ?? 0) + 1
        var url = folder.appendingPathComponent(Chapters.fileName(number: next, base: "Chapter \(next)"))
        if fm.fileExists(atPath: url.path) { url = uniqueURL(in: folder, base: "Chapter \(next)", ext: "md") }
        try Templates.render(Templates.chapter.body, title: "Chapter \(next)", chapter: next).write(to: url, atomically: true, encoding: .utf8)
        refresh()
        return url
    }

    /// Renames chapters so their number prefixes match `order` (01, 02, …). Returns old → new URLs.
    func renumberChapters(_ order: [URL]) throws -> [URL: URL] {
        var moves: [URL: URL] = [:]
        // Two passes through temporary names so swaps never collide.
        var staged: [(temp: URL, final: URL, original: URL)] = []
        for (index, url) in order.enumerated() {
            let final = url.deletingLastPathComponent()
                .appendingPathComponent(Chapters.fileName(number: index + 1, base: Chapters.baseName(of: url), ext: url.pathExtension.isEmpty ? "md" : url.pathExtension))
            guard final != url else { continue }
            let temp = url.deletingLastPathComponent().appendingPathComponent(".wren-renumber-\(UUID().uuidString).md")
            do {
                try fm.moveItem(at: url, to: temp)
            } catch {
                for item in staged { try? fm.moveItem(at: item.temp, to: item.original) }
                throw error
            }
            staged.append((temp, final, url))
        }
        do {
            for item in staged {
                try fm.moveItem(at: item.temp, to: item.final)
                moves[item.original] = item.final
            }
        } catch {
            // Put back anything still parked under a hidden temporary name, so no chapter
            // disappears from the book.
            for item in staged where fm.fileExists(atPath: item.temp.path) {
                try? fm.moveItem(at: item.temp, to: item.original)
            }
            refresh()
            throw error
        }
        refresh()
        return moves
    }

    // MARK: User folders (security-scoped bookmarks)

    func addFolderWithPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Add to Wren"
        panel.message = "Choose a folder of Markdown files. Wren edits them in place."
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard !roots.contains(url) else { return url }
        if let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
            var stored = defaults.array(forKey: "folderBookmarks") as? [Data] ?? []
            stored.append(data)
            defaults.set(stored, forKey: "folderBookmarks")
        }
        _ = url.startAccessingSecurityScopedResource()
        roots.append(url)
        refresh()
        return url
    }

    func removeRoot(_ url: URL) {
        guard url != defaultRoot else { return }
        roots.removeAll { $0 == url }
        let stored = (defaults.array(forKey: "folderBookmarks") as? [Data] ?? []).filter { data in
            var stale = false
            let resolved = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            return resolved?.standardizedFileURL != url.standardizedFileURL
        }
        defaults.set(stored, forKey: "folderBookmarks")
        url.stopAccessingSecurityScopedResource()
        refresh()
    }

    private func resolveBookmarks() -> [URL] {
        let stored = defaults.array(forKey: "folderBookmarks") as? [Data] ?? []
        var urls: [URL] = []
        var refreshed: [Data] = []
        for data in stored {
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
                  url.startAccessingSecurityScopedResource() else { continue }
            urls.append(url)
            if stale, let fresh = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                refreshed.append(fresh)
            } else {
                refreshed.append(data)
            }
        }
        defaults.set(refreshed, forKey: "folderBookmarks")
        return urls
    }

    // MARK: First launch

    private func seedWelcomeContent() {
        let welcome = defaultRoot.appendingPathComponent("Welcome to Wren.md")
        try? WelcomeContent.welcome.write(to: welcome, atomically: true, encoding: .utf8)
        let ideas = defaultRoot.appendingPathComponent("Ideas", isDirectory: true)
        try? fm.createDirectory(at: ideas, withIntermediateDirectories: true)
        try? WelcomeContent.styleLensDemo.write(to: ideas.appendingPathComponent("Try the Style Lens.md"), atomically: true, encoding: .utf8)
    }
}
