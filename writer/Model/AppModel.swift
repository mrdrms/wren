import AppKit
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

enum InspectorTab: String, CaseIterable, Identifiable {
    case goals, outline, style, stats, history, cuts
    var id: String { rawValue }
    var label: String { self == .cuts ? "Cutting Room" : rawValue.capitalized }
    var symbol: String {
        switch self {
        case .goals: "target"
        case .outline: "list.bullet.indent"
        case .style: "wand.and.stars"
        case .stats: "chart.bar.xaxis"
        case .history: "clock.arrow.circlepath"
        case .cuts: "scissors"
        }
    }
}

enum FormatAction {
    case bold, italic, highlight, strikethrough, code, link
    case heading(Int), quote, bullet, numbered, task, note, paragraph
    case divider, codeBlock
}

/// The kind of paragraph the caret is in, shown by the format bar.
enum BlockKind: String {
    case body, title, heading, subheading, bullet, numbered, task, quote

    var label: String {
        switch self {
        case .body: "Body"
        case .title: "Title"
        case .heading: "Heading"
        case .subheading: "Subheading"
        case .bullet: "Bulleted List"
        case .numbered: "Numbered List"
        case .task: "Checklist"
        case .quote: "Quote"
        }
    }

    static func of(line: String) -> BlockKind {
        if line.hasPrefix("# ") { return .title }
        if line.hasPrefix("## ") { return .heading }
        if line.range(of: "^#{3,6} ", options: .regularExpression) != nil { return .subheading }
        if line.range(of: "^[ \\t]*[-*+] \\[[ xX]\\] ", options: .regularExpression) != nil { return .task }
        if line.range(of: "^[ \\t]*[-*+] ", options: .regularExpression) != nil { return .bullet }
        if line.range(of: "^[ \\t]*\\d+[.)] ", options: .regularExpression) != nil { return .numbered }
        if line.hasPrefix(">") { return .quote }
        return .body
    }
}

/// What formatting applies at the caret, so buttons can show as active.
struct FormatState: Equatable {
    var bold = false, italic = false, strike = false, highlight = false, link = false
    var block = BlockKind.body
}

/// The link (or video embed) being created or edited in the link sheet.
struct LinkDraft: Identifiable {
    enum Kind { case link, video }
    let id = UUID()
    var kind: Kind
    var text: String
    var url: String
    /// The text to replace: the selection, or an existing link under the caret.
    var range: NSRange
    var isEditing: Bool
}

struct Celebration: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let subtitle: String
    let emoji: String
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let symbol: String
}

struct Sprint: Equatable {
    let start: Date
    let duration: TimeInterval
    let wordsAtStart: Int
    var end: Date { start.addingTimeInterval(duration) }
}

struct JumpRequest: Equatable {
    let id = UUID()
    let range: NSRange
}

/// Rolling record of recent keystrokes, used for the momentum flame.
struct Momentum {
    private(set) var events: [(date: Date, words: Int)] = []

    mutating func record(_ words: Int, at date: Date = .now) {
        events.append((date, words))
        events.removeAll { date.timeIntervalSince($0.date) > 60 }
    }

    /// Words per minute over the last 30 seconds.
    func wordsPerMinute(at date: Date = .now) -> Double {
        let recent = events.filter { date.timeIntervalSince($0.date) <= 30 }
        return Double(recent.reduce(0) { $0 + $1.words }) * 2
    }

    /// 0 = idle, 1 = warming up, 2 = flowing, 3 = on fire.
    func level(at date: Date = .now) -> Int {
        switch wordsPerMinute(at: date) {
        case ..<4: 0
        case ..<18: 1
        case ..<35: 2
        default: 3
        }
    }
}

@Observable
final class AppModel {
    let prefs = Preferences.shared
    let log = WritingLog.shared
    let library = LibraryStore()

    // Navigation
    var sidebarSelection: SidebarSelection? = .all {
        didSet { if sidebarSelection != oldValue { navigatorPage = .sheets } }
    }
    /// Which page of the navigator is showing: your folders, or the sheets inside one.
    var navigatorPage: NavigatorPage = .sheets
    var selectedSheet: URL? {
        didSet { if selectedSheet != oldValue { open(selectedSheet) } }
    }
    var searchText = ""
    var columnVisibility: NavigationSplitViewVisibility = .all

    // Current document
    private(set) var loadedURL: URL?
    private(set) var text = ""
    private(set) var loadToken = 0
    private(set) var stats = TextStats()
    private(set) var headings: [Heading] = []
    private(set) var lensMatches: [StyleLens.Match] = []
    private(set) var snapshots: [Snapshot] = []
    private(set) var notes: [DraftNote] = []
    private(set) var ghostCount = 0
    private(set) var sentenceLengths: [Int] = []
    private(set) var cuts: [Cut] = []
    var jumpRequest: JumpRequest?

    // Chrome
    var showInspector = false
    var inspectorTab: InspectorTab = .goals
    var showPalette = false
    var showJourney = false
    var showTimeMachine = false
    var showTemplates = false
    /// The book folder being compiled, while the compile sheet is open.
    var compileFolder: URL?
    var boardMode = false
    private(set) var previewMode: PreviewMode = .off
    /// Caret position as a fraction of the sheet, so the side-by-side preview can follow along.
    var caretFraction: Double = 0
    private(set) var isReading = false
    var zen = false { didSet { if zen != oldValue { applyZen() } } }
    /// A brief on-screen reminder of how to step back out (Zen, preview alone).
    private(set) var hint: String?
    var showBreakScreen = false
    var formatState = FormatState()
    var linkDraft: LinkDraft?
    /// A popup inside the editor (the slash menu) owns the keyboard.
    var editorPopupOpen = false
    let pomodoro = Pomodoro()
    private(set) var isTyping = false
    var celebration: Celebration?
    var toast: Toast?
    var renameTarget: URL?
    var renameText = ""
    var newFolderParent: URL?
    var newFolderName = ""

    // Motivation
    private(set) var sprint: Sprint?
    private(set) var momentum = Momentum()

    @ObservationIgnored weak var editor: WrenTextView?
    @ObservationIgnored private var lastWordCount = 0
    @ObservationIgnored private var wordsAtOpen = 0
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var typingTask: Task<Void, Never>?
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var goalCelebrated = false
    /// The live editor, kept so it can move between the split view and the immersive layer.
    @ObservationIgnored var editorCoordinator: MarkdownEditor.Coordinator?
    @ObservationIgnored private var zenEnteredFullScreen = false
    @ObservationIgnored private var askedForNotifications = false
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var historyText: String?
    @ObservationIgnored private let reader = ReadAloud()

    init() {
        pomodoro.onPhaseStart = { [weak self] phase in self?.pomodoroDidStart(phase) }
        pomodoro.onPhaseEnd = { [weak self] finished, next in self?.pomodoroDidEnd(finished, next: next) }
        reader.onWord = { [weak self] range in
            self?.editor?.spokenRange = range
        }
        reader.onFinish = { [weak self] in
            self?.isReading = false
            self?.editor?.spokenRange = nil
        }
        if let first = library.sheets.first(where: { $0.title == "Welcome to Wren" }) ?? library.sheets.first {
            selectedSheet = first.url
            open(first.url)
        }
    }

    var visibleSheets: [Sheet] { library.sheets(for: sidebarSelection, search: searchText) }

    var listTitle: String {
        switch sidebarSelection {
        case .recent: "Recent"
        case .folder(let url): library.tree.first(where: { $0.url == url })?.name ?? url.lastPathComponent
        default: "All Sheets"
        }
    }

    /// Flips the navigator between the Library and the sheet list, bringing it into view.
    func toggleLibrary() {
        if columnVisibility == .detailOnly {
            columnVisibility = .all
            navigatorPage = .library
        } else {
            navigatorPage = navigatorPage == .library ? .sheets : .library
        }
    }

    var currentTitle: String {
        guard let url = loadedURL else { return "Wren" }
        return LibraryStore.titleAndPreview(text: text, fallback: url.deletingPathExtension().lastPathComponent).0
    }

    // MARK: Opening & saving

    private func open(_ url: URL?) {
        guard url != loadedURL else { return }
        saveNow()
        autoSnapshotIfNeeded()
        stopReading()
        loadedURL = url
        text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        loadToken += 1
        cuts = url.map { CuttingRoom.load(for: $0) } ?? []
        startHistory()
        analyze()
        lastWordCount = stats.words
        wordsAtOpen = stats.words
        goalCelebrated = documentGoal.map { stats.words >= $0 } ?? false
        snapshots = url.map { SnapshotStore.list(for: $0) } ?? []
    }

    /// Called by the editor on every edit.
    func textDidChange(_ newText: String) {
        if isReading { stopReading() }
        text = newText
        dirty = true
        analyze()

        let delta = stats.words - lastWordCount
        lastWordCount = stats.words
        if delta > 0 {
            // Cap per-edit credit so pasting a chapter doesn't count as writing it.
            let credited = min(delta, 30)
            let dailyBefore = log.today
            log.add(credited)
            momentum.record(credited)
            checkDailyGoal(before: dailyBefore)
        }
        checkDocumentGoal()

        isTyping = true
        typingTask?.cancel()
        typingTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            self?.isTyping = false
        }

        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    private func analyze() {
        // Struck text and margin notes don't count toward goals or statistics.
        var readable = MarkdownImage.stripForCounting(FrontMatter.strip(text))
        if readable.contains("{") { readable = Ghost.clean(readable) }
        stats = TextStats.forContent(text)
        headings = Heading.parse(text)
        lensMatches = StyleLens.analyze(text)
        notes = DraftNote.parse(text)
        ghostCount = Ghost.count(text)
        sentenceLengths = Rhythm.sentenceLengths(readable)
    }

    func saveNow() {
        saveTask?.cancel()
        guard dirty, let url = loadedURL else { return }
        dirty = false
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            library.updateSheet(at: url, text: text)
            recordHistory()
            autoTitleIfNeeded(url)
        } catch {
            dirty = true
            showToast("Couldn't save: \(error.localizedDescription)", symbol: "exclamationmark.triangle.fill")
        }
    }

    /// "Untitled" sheets are renamed after their first line once you move past it.
    private func autoTitleIfNeeded(_ url: URL) {
        guard prefs.autoTitle,
              url.deletingPathExtension().lastPathComponent.hasPrefix("Untitled"),
              text.contains("\n") else { return }
        // The visible title: front matter title, or the first line without its Markdown.
        let title = LibraryStore.sanitize(LibraryStore.titleAndPreview(text: text, fallback: "").0)
        guard !title.isEmpty, let newURL = try? library.rename(url, to: String(title.prefix(60))), newURL != url else { return }
        moveDocumentIdentity(from: url, to: newURL)
    }

    private func moveDocumentIdentity(from old: URL, to new: URL) {
        SnapshotStore.move(from: old, to: new)
        HistoryStore.move(from: old, to: new)
        CuttingRoom.move(from: old, to: new)
        var goals = documentGoals
        if let goal = goals.removeValue(forKey: old.path) { goals[new.path] = goal }
        documentGoals = goals
        if loadedURL == old {
            loadedURL = new
            selectedSheet = new
        }
    }

    // MARK: Sheets & folders

    var targetFolder: URL {
        if case .folder(let url) = sidebarSelection { return url }
        if let loaded = loadedURL, let sheet = library.sheets.first(where: { $0.url == loaded }) { return sheet.folder }
        return library.defaultRoot
    }

    /// "New" depends on where you are: a chapter in a book, a post in a blog,
    /// today's page in a journal, or a blank sheet anywhere else.
    func newSheet() {
        saveNow()
        let folder = targetFolder
        do {
            let url: URL
            switch library.projects[folder]?.kind {
            case .book:
                url = try library.createChapter(in: folder)
            case .blog:
                url = try library.createSheet(in: folder, named: "Untitled post",
                                              text: Templates.render(Templates.blogPost.body, title: "Untitled post"))
                selectTitlePlaceholder("Untitled post")
            case .journal:
                url = try todaysEntry(in: folder)
            case nil:
                url = try library.createSheet(in: folder)
            }
            if case .recent = sidebarSelection {} else if case .folder = sidebarSelection {} else { sidebarSelection = .all }
            searchText = ""
            selectedSheet = url
            if zen == false && columnVisibility == .detailOnly { columnVisibility = .all }
            DispatchQueue.main.async { [weak self] in self?.editor?.window?.makeFirstResponder(self?.editor) }
        } catch {
            showToast("Couldn't create sheet", symbol: "exclamationmark.triangle.fill")
        }
    }

    private func todaysEntry(in folder: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let url = folder.appendingPathComponent(formatter.string(from: .now)).appendingPathExtension("md")
        if !FileManager.default.fileExists(atPath: url.path) {
            try Templates.render(Templates.journal.body, title: "").write(to: url, atomically: true, encoding: .utf8)
            library.refresh()
        }
        return url
    }

    /// After a template opens, select its placeholder title so typing replaces it.
    private func selectTitlePlaceholder(_ placeholder: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let editor = self.editor else { return }
            let range = (editor.string as NSString).range(of: placeholder)
            if range.location != NSNotFound { self.jumpRequest = JumpRequest(range: range) }
        }
    }

    // MARK: Templates & projects

    func createSheet(from template: SheetTemplate, title: String) {
        saveNow()
        let name = title.trimmingCharacters(in: .whitespaces)
        let isJournal = template.id == "journal"
        let displayTitle = name.isEmpty ? (isJournal ? Date.now.formatted(date: .long, time: .omitted) : "Untitled") : name
        do {
            let url = try library.createSheet(in: targetFolder, named: displayTitle,
                                              text: Templates.render(template.body, title: displayTitle))
            if case .folder = sidebarSelection {} else { sidebarSelection = .all }
            searchText = ""
            selectedSheet = url
            if name.isEmpty && !isJournal && template.id != "blank" { selectTitlePlaceholder("Untitled") }
            DispatchQueue.main.async { [weak self] in self?.editor?.window?.makeFirstResponder(self?.editor) }
        } catch {
            showToast("Couldn't create sheet", symbol: "exclamationmark.triangle.fill")
        }
    }

    func createProject(from template: ProjectTemplate, name: String, author: String, goal: Int?) {
        saveNow()
        let title = name.trimmingCharacters(in: .whitespaces).isEmpty ? template.name : name.trimmingCharacters(in: .whitespaces)
        do {
            let folder = try library.createProject(template, name: title, author: author.isEmpty ? nil : author, goal: goal, in: library.defaultRoot)
            sidebarSelection = .folder(folder)
            searchText = ""
            if template.kind == .journal {
                selectedSheet = try todaysEntry(in: folder)
            } else if let first = library.sheets(for: .folder(folder), search: "").first {
                selectedSheet = first.url
            }
            celebrate(Celebration(title: "\(title) is ready", subtitle: template.kind == .book ? "Your first chapter is waiting." : "Start writing whenever you're ready.", emoji: template.kind == .book ? "📖" : "✨"))
        } catch {
            showToast("Couldn't create the project", symbol: "exclamationmark.triangle.fill")
        }
    }

    /// Moves a chapter earlier (-1) or later (+1) and renumbers the book.
    func moveChapter(_ url: URL, by offset: Int) {
        let folder = url.deletingLastPathComponent()
        var order = library.chapters(in: folder).map(\.url)
        guard let index = order.firstIndex(of: url), order.indices.contains(index + offset) else { return }
        saveNow()
        order.swapAt(index, index + offset)
        guard let moves = try? library.renumberChapters(order) else {
            showToast("Couldn't reorder chapters", symbol: "exclamationmark.triangle.fill")
            return
        }
        for (old, new) in moves { moveDocumentIdentity(from: old, to: new) }
    }

    func setProject(_ info: ProjectInfo?, for folder: URL) {
        library.setProject(info, for: folder)
    }

    func projectWords(_ folder: URL) -> Int {
        library.chapters(in: folder).reduce(0) { $0 + $1.words }
    }

    func compile(folder: URL, format: Exporter.CompileFormat, titlePage: Bool) {
        compileFolder = nil
        saveNow()
        let info = library.projects[folder]
        let chapters = library.chapters(in: folder).compactMap { try? String(contentsOf: $0.url, encoding: .utf8) }
        guard !chapters.isEmpty else { return showToast("This book has no chapters yet", symbol: "book.closed") }
        let title = library.tree.flatMap { [$0] + ($0.children ?? []) }.first { $0.url == folder }?.name ?? folder.lastPathComponent
        if Exporter.compileBook(title: title, author: info?.author, chapters: chapters, titlePage: titlePage,
                                format: format, style: prefs.blogStyle, folder: folder) {
            showToast("Manuscript compiled: \(chapters.count) chapters", symbol: "books.vertical.fill")
        }
    }

    func beginNewFolder(in parent: URL? = nil) {
        newFolderParent = parent ?? targetFolder
        newFolderName = ""
    }

    func commitNewFolder() {
        guard let parent = newFolderParent else { return }
        newFolderParent = nil
        if let url = try? library.createFolder(in: parent, name: newFolderName) {
            sidebarSelection = .folder(url)
        }
    }

    func beginRename(_ url: URL) {
        renameTarget = url
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        renameText = isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    func commitRename() {
        guard let url = renameTarget else { return }
        renameTarget = nil
        if url == loadedURL { saveNow() }
        var newName = renameText
        // Chapters keep their place in the book even if the number was removed while renaming.
        if library.projects[url.deletingLastPathComponent()]?.kind == .book, let number = Chapters.number(of: url),
           Chapters.number(of: URL(fileURLWithPath: newName + ".md")) == nil {
            newName = String(format: "%02d ", number) + newName
        }
        guard let newURL = try? library.rename(url, to: newName), newURL != url else { return }
        if case .folder(let selected) = sidebarSelection, selected == url { sidebarSelection = .folder(newURL) }
        moveDocumentIdentity(from: url, to: newURL)
    }

    func duplicate(_ url: URL) {
        if url == loadedURL { saveNow() }
        if let copy = try? library.duplicate(url) { selectedSheet = copy }
    }

    func trash(_ url: URL) {
        if url == loadedURL {
            saveNow()
            dirty = false
            selectedSheet = nil
        }
        do {
            try library.trash(url)
            showToast("Moved to Trash", symbol: "trash")
        } catch {
            showToast("Couldn't move to Trash", symbol: "exclamationmark.triangle.fill")
        }
    }

    func move(_ url: URL, to folder: URL) {
        if url == loadedURL { saveNow() }
        guard let newURL = try? library.move(url, to: folder) else { return }
        moveDocumentIdentity(from: url, to: newURL)
    }

    func addFolder() {
        if let url = library.addFolderWithPanel() { sidebarSelection = .folder(url) }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Editing commands

    func format(_ action: FormatAction) {
        guard let editor else { return }
        if case .link = action {
            beginLink()
            return
        }
        editor.apply(action)
        editor.window?.makeFirstResponder(editor)
    }

    // MARK: Links & embeds

    /// Opens the link sheet for the selection, or for the existing link under the caret.
    func beginLink() {
        guard let editor else { return }
        let ns = editor.string as NSString
        let selection = editor.selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        for m in MarkdownHighlighter.link.matches(in: editor.string, range: lineRange)
        where ns.character(at: m.range.location) != 33 // "!" is an image
            && selection.location >= m.range.location && NSMaxRange(selection) <= NSMaxRange(m.range) {
            linkDraft = LinkDraft(kind: .link, text: ns.substring(with: m.range(at: 1)), url: ns.substring(with: m.range(at: 2)),
                                  range: m.range, isEditing: true)
            return
        }
        let selected = ns.substring(with: selection)
        let clipboard = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let suggested = clipboard.hasPrefix("http") && !clipboard.contains(" ") ? clipboard : ""
        linkDraft = LinkDraft(kind: .link, text: selected, url: suggested, range: selection, isEditing: false)
    }

    func beginVideoEmbed() {
        guard let editor else { return }
        let clipboard = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        linkDraft = LinkDraft(kind: .video, text: "", url: MarkdownImage.youTubeID(clipboard) != nil ? clipboard : "",
                              range: editor.selectedRange(), isEditing: false)
    }

    func applyLink(_ draft: LinkDraft) {
        linkDraft = nil
        guard let editor else { return }
        var url = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        if !url.contains("://"), !url.hasPrefix("mailto:"), !url.hasPrefix("#"), url.contains(".") { url = "https://" + url }
        let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch draft.kind {
        case .link:
            editor.replace(draft.range, with: "[\(text.isEmpty ? url : text)](\(url))")
        case .video:
            editor.setSelectedRange(draft.range)
            editor.insertBlock("![\(text.isEmpty ? "Video" : text)](\(url))")
        }
        editor.window?.makeFirstResponder(editor)
    }

    func removeLink(_ draft: LinkDraft) {
        linkDraft = nil
        editor?.replace(draft.range, with: draft.text)
        editor?.window?.makeFirstResponder(editor)
    }

    /// Adds blog front matter (title and date) at the top, or jumps to it if it's there.
    func insertPostDetails() {
        guard let editor else { return }
        if let range = FrontMatter.range(in: editor.string) {
            jumpRequest = JumpRequest(range: NSRange(location: range.location, length: 0))
            return
        }
        editor.replace(NSRange(location: 0, length: 0), with: FrontMatter.make(title: currentTitle))
        editor.setSelectedRange(NSRange(location: 8, length: (currentTitle as NSString).length))
        editor.window?.makeFirstResponder(editor)
        showToast("Post details added: title and date for your blog", symbol: "doc.badge.gearshape")
    }

    func jump(to heading: Heading) {
        jumpRequest = JumpRequest(range: NSRange(location: heading.range.location, length: 0))
    }

    func toggleZen() { zen.toggle() }

    /// Zen, or the preview on its own: the page takes over the whole window.
    var isImmersive: Bool { zen || previewMode == .full }

    /// Zen hides everything but the page (or the preview), optionally full screen. Esc leaves.
    private func applyZen() {
        let window = editor?.window ?? NSApp.keyWindow
        if zen { withAnimation(.smooth(duration: 0.35)) { showInspector = false } }
        if zen {
            if prefs.zenFullScreen, let window, !window.styleMask.contains(.fullScreen) {
                zenEnteredFullScreen = true
                window.toggleFullScreen(nil)
            }
            flashHint("Zen mode · Esc to exit")
        } else {
            hint = nil
            if zenEnteredFullScreen, let window, window.styleMask.contains(.fullScreen) {
                window.toggleFullScreen(nil)
            }
            zenEnteredFullScreen = false
        }
    }

    private func flashHint(_ text: String) {
        withAnimation(.easeOut(duration: 0.3)) { hint = text }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.8))
            guard self?.hint == text else { return }
            withAnimation(.easeIn(duration: 0.6)) { self?.hint = nil }
        }
    }

    /// Esc steps back out of whatever is taking over the window. Returns whether it handled it.
    func handleEscape() -> Bool {
        if showBreakScreen { withAnimation { showBreakScreen = false }; return true }
        if zen { zen = false; return true }
        if previewMode == .full { setPreview(.off); return true }
        if boardMode { toggleBoard(); return true }
        return false
    }

    // MARK: Pomodoro

    func stopPomodoro() {
        pomodoro.stop()
        withAnimation(.smooth(duration: 0.3)) { showBreakScreen = false }
        showToast("Pomodoro stopped", symbol: "stop.circle")
    }

    func startPomodoro() {
        prefs.pomodoroEnabled = true
        requestNotificationPermission()
        pomodoro.start()
    }

    private func pomodoroDidStart(_ phase: Pomodoro.Phase) {
        if phase == .work {
            if showBreakScreen { withAnimation { showBreakScreen = false } }
            if prefs.pomodoroZen && !zen { zen = true }
            editor?.window?.makeFirstResponder(editor)
        }
    }

    private func pomodoroDidEnd(_ finished: Pomodoro.Phase, next: Pomodoro.Phase) {
        NSSound(named: finished == .work ? "Glass" : "Hero")?.play()
        let title: String
        let body: String
        switch finished {
        case .work:
            title = "🍅 Session complete!"
            body = next == .longBreak
                ? "That's \(prefs.pomodoroLongEvery) in a row. Take a proper \(prefs.pomodoroLongBreak)-minute break."
                : "Stretch, breathe, look out the window. Back in \(prefs.pomodoroShortBreak) minutes."
            if prefs.pomodoroBreakScreen { withAnimation(.smooth(duration: 0.5)) { showBreakScreen = true } }
        default:
            title = "Break's over"
            body = prefs.pomodoroAutoStart ? "Next focus session has started." : "Ready when you are. Start your next session."
            withAnimation(.smooth(duration: 0.4)) { showBreakScreen = false }
        }
        showToast(title, symbol: finished == .work ? "cup.and.saucer.fill" : "timer")
        if !NSApp.isActive { postNotification(title: title, body: body) }
    }

    private func requestNotificationPermission() {
        guard !askedForNotifications else { return }
        askedForNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func postNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }

    // MARK: Goals

    private var documentGoals: [String: Int] {
        get { defaults.dictionary(forKey: "documentGoals") as? [String: Int] ?? [:] }
        set { defaults.set(newValue, forKey: "documentGoals") }
    }

    /// Stored in UserDefaults; `goalRevision` makes SwiftUI notice changes.
    private(set) var goalRevision = 0

    var documentGoal: Int? {
        _ = goalRevision
        guard let url = loadedURL else { return nil }
        return documentGoals[url.path]
    }

    func setDocumentGoal(_ goal: Int?) {
        guard let url = loadedURL else { return }
        var goals = documentGoals
        goals[url.path] = goal
        documentGoals = goals
        goalRevision += 1
        goalCelebrated = goal.map { stats.words >= $0 } ?? false
    }

    var documentProgress: Double? {
        guard let goal = documentGoal, goal > 0 else { return nil }
        return min(1, Double(stats.words) / Double(goal))
    }

    var dailyProgress: Double {
        guard prefs.dailyGoal > 0 else { return 0 }
        return min(1, Double(log.today) / Double(prefs.dailyGoal))
    }

    private func checkDocumentGoal() {
        guard let goal = documentGoal, !goalCelebrated, stats.words >= goal else { return }
        goalCelebrated = true
        celebrate(Celebration(title: "Goal reached!", subtitle: "\(goal.formatted()) words in “\(currentTitle)”", emoji: "🎯"))
    }

    private func checkDailyGoal(before: Int) {
        let goal = prefs.dailyGoal
        guard goal > 0, before < goal, log.today >= goal else { return }
        let streak = log.streak
        celebrate(Celebration(
            title: "Daily goal smashed!",
            subtitle: streak > 1 ? "That's a \(streak)-day streak. Keep it going." : "Come back tomorrow to start a streak.",
            emoji: "🔥"))
    }

    // MARK: Sprints

    func startSprint(minutes: Int) {
        sprint = Sprint(start: .now, duration: TimeInterval(minutes * 60), wordsAtStart: log.today)
        showToast("\(minutes)-minute sprint started. Go!", symbol: "timer")
        let current = sprint
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard let self, self.sprint == current else { return }
            self.finishSprint()
        }
        editor?.window?.makeFirstResponder(editor)
    }

    var sprintWords: Int {
        guard let sprint else { return 0 }
        return max(0, log.today - sprint.wordsAtStart)
    }

    func finishSprint() {
        guard let sprint else { return }
        let words = sprintWords
        let minutes = max(1, Int(Date.now.timeIntervalSince(sprint.start) / 60))
        self.sprint = nil
        celebrate(Celebration(
            title: "Sprint complete!",
            subtitle: "\(words.formatted()) words in \(minutes) min. That's \(words / minutes) words a minute.",
            emoji: words >= minutes * 15 ? "🏆" : "⏱️"))
    }

    func cancelSprint() {
        sprint = nil
        showToast("Sprint cancelled", symbol: "xmark.circle")
    }

    // MARK: Snapshots

    func takeSnapshot(silent: Bool = false) {
        guard let url = loadedURL else { return }
        saveNow()
        if (try? SnapshotStore.take(of: url, text: text)) != nil {
            snapshots = SnapshotStore.list(for: url)
            if !silent { showToast("Snapshot saved", symbol: "camera.fill") }
        }
    }

    func restore(_ snapshot: Snapshot) {
        takeSnapshot(silent: true)
        let restored = SnapshotStore.text(of: snapshot)
        editor?.replaceAll(with: restored)
        showToast("Restored snapshot from \(snapshot.date.formatted(date: .abbreviated, time: .shortened))", symbol: "clock.arrow.circlepath")
    }

    func deleteSnapshot(_ snapshot: Snapshot) {
        SnapshotStore.delete(snapshot)
        if let url = loadedURL { snapshots = SnapshotStore.list(for: url) }
    }

    /// A silent safety net: leaving a sheet after big changes snapshots it automatically.
    private func autoSnapshotIfNeeded() {
        guard let url = loadedURL, abs(stats.words - wordsAtOpen) >= 100 else { return }
        _ = try? SnapshotStore.take(of: url, text: text)
    }

    // MARK: Time Machine

    /// Brings the recorded history in line with the file on disk (it may have been edited elsewhere).
    private func startHistory() {
        guard let url = loadedURL else { historyText = nil; return }
        let recorded = HistoryStore.replay(HistoryStore.load(for: url))
        if let change = TextChange.between(recorded, text) { HistoryStore.append(change, for: url) }
        historyText = text
    }

    private func recordHistory() {
        guard let url = loadedURL, let previous = historyText, let change = TextChange.between(previous, text) else { return }
        HistoryStore.append(change, for: url)
        historyText = text
    }

    func historyChanges() -> [TextChange] {
        saveNow()
        return loadedURL.map { HistoryStore.load(for: $0) } ?? []
    }

    func openTimeMachine() {
        guard loadedURL != nil else { return }
        stopReading()
        showTimeMachine = true
    }

    func restoreFromHistory(_ restored: String, date: Date) {
        showTimeMachine = false
        takeSnapshot(silent: true)
        editor?.replaceAll(with: restored)
        showToast("Travelled back to \(date.formatted(date: .abbreviated, time: .shortened))", symbol: "clock.arrow.circlepath")
    }

    // MARK: Cutting Room Floor

    func addCut(_ removed: String) {
        let trimmed = removed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = loadedURL, TextStats.wordCount(trimmed) >= 4, cuts.first?.text != trimmed else { return }
        cuts.insert(Cut(date: .now, text: trimmed), at: 0)
        CuttingRoom.save(cuts, for: url)
        showToast("Saved to the Cutting Room", symbol: "scissors")
    }

    func insertCut(_ cut: Cut) {
        editor?.insertAtCaret(cut.text)
    }

    func deleteCut(_ cut: Cut) {
        guard let url = loadedURL else { return }
        cuts.removeAll { $0.id == cut.id }
        CuttingRoom.save(cuts, for: url)
    }

    // MARK: Flow Lock

    func sweepGhosts() {
        guard ghostCount > 0 else { return }
        let count = ghostCount
        editor?.replaceAll(with: Ghost.sweep(text), keepSelection: true)
        showToast("Swept away \(count) struck passage\(count == 1 ? "" : "s")", symbol: "wind")
    }

    func restoreGhosts() {
        guard ghostCount > 0 else { return }
        editor?.replaceAll(with: Ghost.restore(text), keepSelection: true)
        showToast("Struck text restored", symbol: "arrow.uturn.backward")
    }

    func toggleFlowLock() {
        prefs.flowLock.toggle()
        if prefs.flowLock {
            showToast("Flow Lock on: finished words get struck, not deleted", symbol: "lock.fill")
        } else if ghostCount > 0 {
            showToast("Flow Lock off. \(ghostCount) struck. Sweep them with ⌥⌘⌫", symbol: "lock.open")
        } else {
            showToast("Flow Lock off", symbol: "lock.open")
        }
    }

    // MARK: Read Aloud

    func toggleReadAloud() {
        if isReading {
            stopReading()
        } else if let editor, loadedURL != nil {
            isReading = true
            reader.speak(text, from: editor.selectedRange().location)
        }
    }

    func stopReading() {
        guard isReading else { return }
        isReading = false
        reader.stop()
        editor?.spokenRange = nil
    }

    // MARK: Storyboard

    func toggleBoard() {
        stopReading()
        withAnimation(.smooth(duration: 0.3)) {
            boardMode.toggle()
            if boardMode { previewMode = .off }
        }
    }

    // MARK: Preview

    /// Preview on its own takes over the window: the sidebar and sheet list step aside
    /// and come back when you return to writing.
    func setPreview(_ mode: PreviewMode) {
        withAnimation(.smooth(duration: 0.3)) {
            if mode == .full { showInspector = false }
            previewMode = mode
            if mode == .full, !zen { flashHint("Preview · Esc to go back to writing") }
            if mode != .off { boardMode = false }
        }
    }

    /// Write → Side by Side → Preview → Write.
    func cyclePreview() {
        let all = PreviewMode.allCases
        setPreview(all[(all.firstIndex(of: previewMode)! + 1) % all.count])
    }

    func moveSection(from: Int, to: Int) {
        let reordered = Storyboard.move(text, from: from, to: to)
        guard reordered != text else { return }
        editor?.replaceAll(with: reordered, keepSelection: true)
    }

    func openSection(_ section: StorySection) {
        withAnimation(.smooth(duration: 0.3)) { boardMode = false }
        let location = (text as NSString).range(of: section.text).location
        if location != NSNotFound {
            DispatchQueue.main.async { [weak self] in
                self?.jumpRequest = JumpRequest(range: NSRange(location: location, length: 0))
            }
        }
    }

    func jump(to note: DraftNote) {
        jumpRequest = JumpRequest(range: NSRange(location: note.range.location, length: 0))
    }

    // MARK: Images & video

    /// Copies media into the sheet's `assets` folder and returns the Markdown to insert.
    func importImages(_ sources: [ImageSource]) -> [String] {
        guard let url = loadedURL else { return [] }
        var snippets: [String] = []
        var videos = 0
        for source in sources {
            guard let result = try? ImageImporter.importImage(source, for: url) else { continue }
            snippets.append("![\(result.alt)](\(result.path))")
            if MarkdownImage.kind(of: result.path) == .video { videos += 1 }
        }
        if snippets.isEmpty {
            showToast("Couldn't add that file", symbol: "exclamationmark.triangle.fill")
        } else if videos == snippets.count {
            showToast(videos == 1 ? "Video added to assets" : "\(videos) videos added to assets", symbol: "film")
        } else {
            showToast(snippets.count == 1 ? "Image added to assets" : "\(snippets.count) files added to assets", symbol: "photo")
        }
        return snippets
    }

    func insertMediaWithPanel() {
        guard loadedURL != nil else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .movie]
        panel.allowsMultipleSelection = true
        panel.prompt = "Insert"
        panel.message = "Choose images or videos. Wren copies them into an assets folder next to this sheet."
        guard panel.runModal() == .OK else { return }
        editor?.insertImageSources(panel.urls.map { .file($0) })
    }

    // MARK: Export

    func export(_ kind: String) {
        guard loadedURL != nil else { return }
        saveNow()
        guard confirmNoSecrets(action: kind == "copy" ? "Copy" : "Export") else { return }
        let ok: Bool
        switch kind {
        case "blog":
            guard let folder = loadedURL?.deletingLastPathComponent() else { return }
            ok = Exporter.exportBlog(title: currentTitle, markdown: Ghost.clean(text), folder: folder, style: prefs.blogStyle)
            if ok { showToast("Blog post exported with its media", symbol: "shippingbox.fill") }
            return
        case "docx": ok = Exporter.exportWord(title: currentTitle, markdown: Ghost.clean(text), folder: loadedURL?.deletingLastPathComponent(), style: prefs.blogStyle)
        case "pdf": ok = Exporter.exportPDF(title: currentTitle, markdown: Ghost.clean(text), folder: loadedURL?.deletingLastPathComponent(), style: prefs.blogStyle)
        case "md": ok = Exporter.exportMarkdown(title: currentTitle, markdown: Ghost.clean(text))
        case "copy":
            Exporter.copyHTML(markdown: Ghost.clean(text))
            showToast("HTML copied to clipboard", symbol: "doc.on.clipboard")
            return
        default: ok = Exporter.exportHTML(title: currentTitle, markdown: Ghost.clean(text), folder: loadedURL?.deletingLastPathComponent(), style: prefs.blogStyle)
        }
        if ok { showToast("Exported", symbol: "square.and.arrow.up") }
    }

    // MARK: Secrets

    /// Before anything leaves Wren, check it for keys, tokens and internal addresses.
    /// Returns whether to go ahead.
    private func confirmNoSecrets(action: String) -> Bool {
        let findings = SecretScanner.scan(Ghost.clean(text))
        guard !findings.isEmpty else { return true }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = findings.count == 1 ? "This sheet may contain a secret" : "This sheet may contain \(findings.count) secrets"
        alert.informativeText = findings.prefix(6).map { "Line \($0.line): \($0.kind) (\($0.preview))" }.joined(separator: "\n")
            + (findings.count > 6 ? "\n…and \(findings.count - 6) more" : "")
            + "\n\nRedact them before publishing, or continue if they're safe to share."
        alert.addButton(withTitle: "Review")
        alert.addButton(withTitle: "\(action) Anyway")
        if alert.runModal() == .alertFirstButtonReturn {
            if let first = findings.first, let range = rangeInText(of: first) {
                jumpRequest = JumpRequest(range: range)
            }
            return false
        }
        return true
    }

    /// Findings are located in the cleaned text; find the same snippet in the sheet itself.
    private func rangeInText(of finding: SecretScanner.Finding) -> NSRange? {
        let cleaned = Ghost.clean(text) as NSString
        let snippet = cleaned.substring(with: finding.range)
        let range = (text as NSString).range(of: snippet)
        return range.location == NSNotFound ? nil : range
    }

    func checkForSecrets() {
        let findings = SecretScanner.scan(Ghost.clean(text))
        if findings.isEmpty {
            showToast("No secrets found. Safe to publish.", symbol: "checkmark.shield.fill")
        } else {
            _ = confirmNoSecrets(action: "Ignore")
        }
    }

    // MARK: Feedback

    func celebrate(_ celebration: Celebration) {
        withAnimation(.spring(duration: 0.5, bounce: 0.35)) { self.celebration = celebration }
        if prefs.keySounds { NSSound(named: "Glass")?.play() }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard self?.celebration == celebration else { return }
            withAnimation(.easeOut(duration: 0.4)) { self?.celebration = nil }
        }
    }

    func showToast(_ message: String, symbol: String) {
        let toast = Toast(message: message, symbol: symbol)
        withAnimation(.spring(duration: 0.4)) { self.toast = toast }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard self?.toast == toast else { return }
            withAnimation(.easeOut(duration: 0.3)) { self?.toast = nil }
        }
    }
}
