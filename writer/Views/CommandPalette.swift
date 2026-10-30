import AppKit
import SwiftUI

struct PaletteItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String?
    let symbol: String
    let shortcut: String?
    let action: () -> Void
}

/// ⌘K: jump to any sheet or run any command by typing a few letters.
struct CommandPalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var selection = 0
    @State private var monitor: Any?
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let results = filtered
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(model.prefs.theme.accentColor)
                TextField("Search sheets or type a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($fieldFocused)
            }
            .padding(16)

            if !results.isEmpty {
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(results.enumerated()), id: \.element.id) { index, item in
                                row(item, selected: index == selection)
                                    .id(index)
                                    .onTapGesture {
                                        selection = index
                                        run(results)
                                    }
                                    .onHover { if $0 { selection = index } }
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selection) { proxy.scrollTo(selection) }
                }
            }
        }
        .frame(width: 580)
        .themedGlass(in: .rect(cornerRadius: 22))
        .shadow(color: .black.opacity(0.18), radius: 40, y: 18)
        .onChange(of: query) { selection = 0 }
        .task {
            // Focus only once the field is in the window; the editor otherwise keeps the keyboard.
            try? await Task.sleep(for: .milliseconds(60))
            fieldFocused = true
        }
        .onAppear {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                switch event.keyCode {
                case 125: selection = min(selection + 1, max(0, filtered.count - 1)); return nil
                case 126: selection = max(selection - 1, 0); return nil
                case 53: close(); return nil
                // Swallow Return here so it can never fall through to the editor underneath.
                case 36, 76: run(filtered); return nil
                default: return event
                }
            }
        }
        .onDisappear {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        let accent = model.prefs.theme.accentColor
        return HStack(spacing: 12) {
            Image(systemName: item.symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .foregroundStyle(selected ? accent : Color.secondary)
                .background(selected ? accent.opacity(0.14) : Color.primary.opacity(0.05), in: .rect(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle).font(.caption).lineLimit(1).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if let shortcut = item.shortcut {
                Text(shortcut)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(selected ? 0.08 : 0.04), in: .rect(cornerRadius: 5))
            }
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(selected ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 10))
        .contentShape(.rect)
    }

    private func run(_ results: [PaletteItem]) {
        guard results.indices.contains(selection) else { return }
        let item = results[selection]
        close()
        DispatchQueue.main.async { item.action() }
    }

    private func close() {
        withAnimation(.snappy(duration: 0.2)) { model.showPalette = false }
    }

    private var filtered: [PaletteItem] {
        let all = commands + model.library.sheets.map { sheet in
            PaletteItem(id: sheet.url.path, title: sheet.title, subtitle: "\(sheet.folder.lastPathComponent) · \(sheet.words == 1 ? "1 word" : "\(sheet.words.formatted()) words")",
                        symbol: "doc.text", shortcut: nil) { [model] in
                model.sidebarSelection = .all
                model.searchText = ""
                model.selectedSheet = sheet.url
            }
        }
        guard !query.isEmpty else { return Array(all.prefix(40)) }
        return all
            .compactMap { item in Self.fuzzyScore(query, item.title).map { (item, $0) } }
            .sorted { $0.1 > $1.1 }
            .prefix(40)
            .map(\.0)
    }

    /// Subsequence match, rewarding consecutive letters and word starts.
    static func fuzzyScore(_ query: String, _ target: String) -> Int? {
        let q = Array(query.lowercased()), t = Array(target.lowercased())
        var qi = 0, score = 0, streak = 0
        for (ti, ch) in t.enumerated() where qi < q.count {
            if ch == q[qi] {
                streak += 1
                score += 1 + streak * 2 + (ti == 0 || t[ti - 1] == " " ? 6 : 0)
                qi += 1
            } else {
                streak = 0
            }
        }
        return qi == q.count ? score - t.count / 10 : nil
    }

    private var commands: [PaletteItem] {
        let m = model
        let p = model.prefs
        var items: [PaletteItem] = [
            PaletteItem(id: "new", title: "New Sheet", subtitle: nil, symbol: "square.and.pencil", shortcut: "⌘N") { m.newSheet() },
            PaletteItem(id: "folder", title: "New Folder…", subtitle: nil, symbol: "folder.badge.plus", shortcut: "⇧⌘N") { m.beginNewFolder() },
            PaletteItem(id: "addfolder", title: "Add Folder to Library…", subtitle: "Edit Markdown files anywhere on your Mac", symbol: "externaldrive.badge.plus", shortcut: "⌘O") { m.addFolder() },
            PaletteItem(id: "focus", title: "Focus Mode: \(p.focus == .off ? "Turn On" : "Next Level")", subtitle: "Currently \(p.focus.label)", symbol: "scope", shortcut: "⇧⌘F") { p.cycleFocus() },
            PaletteItem(id: "typewriter", title: "Typewriter Mode: \(p.typewriter ? "Off" : "On")", subtitle: nil, symbol: "character.cursor.ibeam", shortcut: "⇧⌘T") { p.typewriter.toggle() },
            PaletteItem(id: "lens", title: "Style Lens: \(p.styleLens ? "Off" : "On")", subtitle: "Adverbs, filler words, passive voice", symbol: "wand.and.stars", shortcut: "⇧⌘L") { p.styleLens.toggle() },
            PaletteItem(id: "flowlock", title: "Flow Lock: \(p.flowLock ? "Off" : "On")", subtitle: "Strike finished words instead of deleting them", symbol: "lock", shortcut: "⇧⌘D") { m.toggleFlowLock() },
            PaletteItem(id: "sweep", title: "Sweep Struck Text", subtitle: m.ghostCount > 0 ? "\(m.ghostCount) struck passages" : "Nothing struck yet", symbol: "wind", shortcut: "⌥⌘⌫") { m.sweepGhosts() },
            PaletteItem(id: "restoreghosts", title: "Restore Struck Text", subtitle: nil, symbol: "arrow.uturn.backward", shortcut: nil) { m.restoreGhosts() },
            PaletteItem(id: "timemachine", title: "Time Machine", subtitle: "Replay every moment of this sheet", symbol: "clock.arrow.circlepath", shortcut: "⇧⌘Y") { m.openTimeMachine() },
            PaletteItem(id: "cuts", title: "Cutting Room Floor", subtitle: "Everything you've deleted, kept safe", symbol: "scissors", shortcut: nil) { m.inspectorTab = .cuts; m.showInspector = true },
            PaletteItem(id: "board", title: m.boardMode ? "Back to Writing" : "Storyboard", subtitle: "Rearrange sections as cards", symbol: "square.grid.2x2", shortcut: "⇧⌘B") { m.toggleBoard() },
            PaletteItem(id: "read", title: m.isReading ? "Stop Reading" : "Read Aloud", subtitle: "Hear your words, follow along", symbol: "speaker.wave.2", shortcut: "⌥⌘R") { m.toggleReadAloud() },
            PaletteItem(id: "rhythm", title: "Rhythm Gutter: \(p.rhythm ? "Off" : "On")", subtitle: "See sentence lengths in the margin", symbol: "waveform", shortcut: "⇧⌘R") { p.rhythm.toggle() },
            PaletteItem(id: "pomodoro", title: m.pomodoro.isRunning ? "Pause Pomodoro" : (m.pomodoro.isActive ? "Resume Pomodoro" : "Start Pomodoro"),
                        subtitle: "\(p.pomodoroWork)-minute focus, \(p.pomodoroShortBreak)-minute breaks", symbol: "timer", shortcut: "⌥⌘P") {
                if m.pomodoro.isRunning { m.pomodoro.pause() } else { m.startPomodoro() }
            },
            PaletteItem(id: "pomodoro-stop", title: "Stop Pomodoro", subtitle: nil, symbol: "stop.circle", shortcut: nil) { m.stopPomodoro() },
            PaletteItem(id: "preview-split", title: "Preview Side by Side", subtitle: "See the post as readers will", symbol: "rectangle.split.2x1", shortcut: "⇧⌘P") { m.setPreview(.split) },
            PaletteItem(id: "preview-full", title: "Preview Full Screen", subtitle: nil, symbol: "eye", shortcut: nil) { m.setPreview(.full) },
            PaletteItem(id: "preview-off", title: "Close Preview", subtitle: nil, symbol: "doc.text", shortcut: nil) { m.setPreview(.off) },
            PaletteItem(id: "secrets", title: "Check for Secrets", subtitle: "API keys, tokens, passwords, internal IPs", symbol: "lock.shield", shortcut: nil) { m.checkForSecrets() },
            PaletteItem(id: "templates", title: "New from Template…", subtitle: "Blog post, essay, story, chapter, journal…", symbol: "doc.on.doc", shortcut: "⌥⌘N") { m.showTemplates = true },
            PaletteItem(id: "project", title: "Start a Project…", subtitle: "A book, a blog or a journal", symbol: "sparkles", shortcut: nil) { m.showTemplates = true },
            PaletteItem(id: "docx", title: "Export as Word…", subtitle: nil, symbol: "doc.richtext", shortcut: nil) { m.export("docx") },
            PaletteItem(id: "markup", title: p.liveFormatting ? "Edit as Plain Markdown" : "Turn On Live Formatting", subtitle: "Show headings and bold styled in the editor", symbol: "textformat", shortcut: "⌥⌘M") { p.liveFormatting.toggle() },
            PaletteItem(id: "formatbar", title: p.showFormatBar ? "Hide Format Bar" : "Show Format Bar", subtitle: nil, symbol: "textformat", shortcut: nil) { p.showFormatBar.toggle() },
            PaletteItem(id: "numbered", title: "Numbered List", subtitle: nil, symbol: "list.number", shortcut: "⇧⌘7") { m.format(.numbered) },
            PaletteItem(id: "bulleted", title: "Bulleted List", subtitle: nil, symbol: "list.bullet", shortcut: "⇧⌘8") { m.format(.bullet) },
            PaletteItem(id: "addlink", title: "Add Link…", subtitle: nil, symbol: "link", shortcut: "⌘L") { m.beginLink() },
            PaletteItem(id: "youtube", title: "Embed YouTube Video…", subtitle: nil, symbol: "play.rectangle", shortcut: nil) { m.beginVideoEmbed() },
            PaletteItem(id: "postdetails", title: "Add Post Details", subtitle: "Title and date for your blog", symbol: "doc.badge.gearshape", shortcut: nil) { m.insertPostDetails() },
            PaletteItem(id: "media", title: "Insert Image or Video…", subtitle: "Or just drag, drop or paste it into the page", symbol: "photo.on.rectangle", shortcut: "⇧⌘I") { m.insertMediaWithPanel() },
            PaletteItem(id: "blog", title: "Export for Blog…", subtitle: "index.md + index.html + assets, ready to publish", symbol: "shippingbox", shortcut: "⌥⌘E") { m.export("blog") },
            PaletteItem(id: "note", title: "Insert Margin Note", subtitle: nil, symbol: "text.bubble", shortcut: "⇧⌘M") { m.format(.note) },
            PaletteItem(id: "sounds", title: "Key Sounds: \(p.keySounds ? "Off" : "On")", subtitle: nil, symbol: "speaker.wave.2", shortcut: nil) { p.keySounds.toggle() },
            PaletteItem(id: "zen", title: "Zen Mode", subtitle: "Hide everything but the page", symbol: "leaf", shortcut: "⇧⌘↩") { m.toggleZen() },
            PaletteItem(id: "journey", title: "Writing Journey", subtitle: "Streaks and history", symbol: "chart.line.uptrend.xyaxis", shortcut: "⇧⌘J") { m.showJourney = true },
            PaletteItem(id: "snapshot", title: "Take Snapshot", subtitle: nil, symbol: "camera", shortcut: "⇧⌘S") { m.takeSnapshot() },
            PaletteItem(id: "library", title: m.navigatorPage == .library ? "Show Sheets" : "Show Library", subtitle: "Your folders and projects", symbol: "books.vertical", shortcut: "⌥⌘L") { m.toggleLibrary() },
            PaletteItem(id: "companion", title: m.companion == nil ? "Open Second Editor" : "Close Second Editor", subtitle: "Notes or another chapter beside your page", symbol: "rectangle.split.2x1", shortcut: "⌥⌘3") { m.toggleCompanion() },
            PaletteItem(id: "publish", title: "Publish…", subtitle: "Ghost, WordPress, Micro.blog, DEV, Hashnode", symbol: "paperplane", shortcut: "⌃⌘P") { m.beginPublish() },
            PaletteItem(id: "substack", title: "Copy for Substack or Medium", subtitle: "Paste it into their editor with formatting", symbol: "doc.on.clipboard", shortcut: "⌥⇧⌘C") { m.export("rich") },
            PaletteItem(id: "ai-lineedit", title: "AI: Line Edit Selection", subtitle: "Suggestions as margin notes", symbol: "sparkle", shortcut: "⌃⌘E") { m.aiLineEdit() },
            PaletteItem(id: "ai-read", title: "AI: Editor's Read", subtitle: "What works, and what to revise", symbol: "sparkle", shortcut: nil) { m.aiCritique() },
            PaletteItem(id: "ai-titles", title: "AI: Title Ideas", subtitle: nil, symbol: "sparkle", shortcut: nil) { m.aiTitles() },
            PaletteItem(id: "ai-alt", title: "AI: Write Alt Text", subtitle: "For images that have none", symbol: "sparkle", shortcut: nil) { m.aiAltText() },
            PaletteItem(id: "ai-continuity", title: "AI: Check Book Continuity", subtitle: "Contradictions across chapters", symbol: "sparkle", shortcut: nil) { m.aiContinuity() },
            PaletteItem(id: "ai-synopsis", title: "AI: Draft Book Synopsis", subtitle: nil, symbol: "sparkle", shortcut: nil) { m.aiSynopsis() },
            PaletteItem(id: "inspector", title: "Toggle Inspector", subtitle: nil, symbol: "sidebar.trailing", shortcut: "⌥⌘I") { m.showInspector.toggle() },
            PaletteItem(id: "goal", title: "Set Word Goal…", subtitle: nil, symbol: "target", shortcut: nil) { m.inspectorTab = .goals; m.showInspector = true },
            PaletteItem(id: "outline", title: "Show Outline", subtitle: nil, symbol: "list.bullet.indent", shortcut: nil) { m.inspectorTab = .outline; m.showInspector = true },
            PaletteItem(id: "html", title: "Export as HTML…", subtitle: nil, symbol: "chevron.left.forwardslash.chevron.right", shortcut: "⌘E") { m.export("html") },
            PaletteItem(id: "pdf", title: "Export as PDF…", subtitle: nil, symbol: "doc.richtext", shortcut: "⇧⌘E") { m.export("pdf") },
            PaletteItem(id: "copyhtml", title: "Copy as HTML", subtitle: "Paste straight into your blog or CMS", symbol: "doc.on.clipboard", shortcut: "⌥⌘C") { m.export("copy") },
        ]
        for minutes in [5, 15, 25, 45] {
            items.append(PaletteItem(id: "sprint\(minutes)", title: "Start \(minutes)-Minute Sprint", subtitle: nil, symbol: "timer", shortcut: nil) { m.startSprint(minutes: minutes) })
        }
        for style in BlogStyle.allCases {
            items.append(PaletteItem(id: "blogstyle-\(style.id)", title: "Blog Style: \(style.label)", subtitle: style.id == p.blogStyle.id ? "Current" : style.blurb,
                                     symbol: "textformat", shortcut: nil) { p.blogStyle = style })
        }
        for theme in Theme.all {
            items.append(PaletteItem(id: "theme-\(theme.id)", title: "Theme: \(theme.name)", subtitle: theme.id == p.themeID ? "Current" : nil,
                                     symbol: theme.isDark ? "moon.stars" : "sun.max", shortcut: nil) { p.themeID = theme.id })
        }
        return items
    }
}
