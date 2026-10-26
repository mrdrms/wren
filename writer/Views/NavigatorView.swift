import SwiftUI

/// The one column beside the page. Like Ulysses on a narrow screen, it holds two pages:
/// the Library (where your writing lives) and the sheets of whatever you picked there.
/// So the window is never more than navigator, page and, when asked for, inspector.
struct NavigatorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            switch model.navigatorPage {
            case .library:
                LibraryPage()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .sheets:
                SheetsPage()
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .clipped()
        .animation(.smooth(duration: 0.28), value: model.navigatorPage)
        .background(PanelBackground(opacity: 0.5))
        .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 400)
    }
}

// MARK: Library

private struct LibraryPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Picking anything opens its sheets, even the one you came from, so the list never
        // holds a selection of its own.
        let pick = Binding<SidebarSelection?>(get: { nil }, set: { selection in
            guard let selection else { return }
            model.sidebarSelection = selection
            model.navigatorPage = .sheets
        })
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Library")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                Spacer()
                Menu {
                    Button("New Folder…") { model.beginNewFolder() }
                    Button("Add Folder from Disk…") { model.addFolder() }
                    Divider()
                    Button("Start a Project…") { model.showTemplates = true }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("New folder, project or library location")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 6)

            List(selection: pick) {
                Section {
                    ScopeRow(title: "All Sheets", symbol: "doc.text", count: model.library.sheets.count, scope: .all)
                        .tag(SidebarSelection.all)
                    ScopeRow(title: "Recent", symbol: "clock", count: nil, scope: .recent)
                        .tag(SidebarSelection.recent)
                } header: {
                    SidebarHeader("Writing")
                }
                Section {
                    OutlineGroup(model.library.tree, children: \.children) { node in
                        ScopeRow(title: node.name, symbol: node.kind?.symbol ?? (node.isRoot ? "books.vertical" : "folder"),
                                 count: nil, scope: .folder(node.url))
                            .tag(SidebarSelection.folder(node.url))
                            .dropDestination(for: URL.self) { urls, _ in
                                urls.forEach { model.move($0, to: node.url) }
                                return !urls.isEmpty
                            }
                            .contextMenu { FolderMenu(node: node) }
                    }
                } header: {
                    SidebarHeader("Folders")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            StreakCard()
                .padding(12)
        }
    }
}

/// A library row; the scope you're currently browsing wears the accent.
private struct ScopeRow: View {
    @Environment(AppModel.self) private var model
    let title: String
    let symbol: String
    let count: Int?
    let scope: SidebarSelection

    var body: some View {
        let current = model.sidebarSelection == scope
        HStack {
            Label {
                Text(title).fontWeight(current ? .semibold : .regular)
            } icon: {
                Image(systemName: symbol).foregroundStyle(current ? model.prefs.theme.accentColor : .secondary)
            }
            Spacer(minLength: 4)
            if let count {
                Text(count.formatted())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.quaternary)
        }
    }
}

private struct FolderMenu: View {
    @Environment(AppModel.self) private var model
    let node: FolderNode

    var body: some View {
        Button("New Sheet") {
            model.sidebarSelection = .folder(node.url)
            model.newSheet()
        }
        Button("New Folder…") { model.beginNewFolder(in: node.url) }
        Menu("Use As") {
            ForEach(ProjectKind.allCases, id: \.self) { kind in
                Button(kind.label) {
                    let current = model.library.projects[node.url]
                    model.setProject(ProjectInfo(kind: kind, goal: current?.goal ?? (kind == .book ? 80_000 : nil), author: current?.author), for: node.url)
                }
            }
            if model.library.projects[node.url] != nil {
                Divider()
                Button("Regular Folder") { model.setProject(nil, for: node.url) }
            }
        }
        if model.library.projects[node.url]?.kind == .book {
            Button("Compile Book…") { model.compileFolder = node.url }
        }
        Divider()
        if !node.isRoot { Button("Rename…") { model.beginRename(node.url) } }
        Button("Show in Finder") { model.revealInFinder(node.url) }
        if model.library.isUserAdded(node.url) {
            Divider()
            Button("Remove from Wren") { model.library.removeRoot(node.url) }
        } else if !node.isRoot {
            Divider()
            Button("Move to Trash", role: .destructive) { model.trash(node.url) }
        }
    }
}

// MARK: Sheets

private struct SheetsPage: View {
    @Environment(AppModel.self) private var model
    @State private var backTargeted = false

    var body: some View {
        @Bindable var model = model
        let sheets = model.visibleSheets
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Button {
                        model.navigatorPage = .library
                    } label: {
                        Label("Library", systemImage: "chevron.left")
                            .font(.callout.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(backTargeted ? model.prefs.theme.accentColor.opacity(0.2) : .clear, in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(model.prefs.theme.accentColor)
                    .help("Back to your folders (⌥⌘L)")
                    // Drag a sheet here and the Library opens, so it can be dropped on a folder.
                    .dropDestination(for: URL.self) { _, _ in false } isTargeted: { targeted in
                        backTargeted = targeted
                        if targeted { model.navigatorPage = .library }
                    }
                    Spacer()
                    Menu {
                        Button("Blank Sheet") { model.newSheet() }
                        Button("From Template…") { model.showTemplates = true }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    } primaryAction: {
                        model.newSheet()
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .fixedSize()
                    .help("New sheet (⌘N). Hold for templates (⌥⌘N).")
                }
                .padding(.leading, -6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.listTitle)
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .lineLimit(1)
                    Text("\(sheets.count) \(sheets.count == 1 ? "sheet" : "sheets") · \(sheets.reduce(0) { $0 + $1.words }.formatted()) words")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                SearchField(text: $model.searchText)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 8)

            List(selection: $model.selectedSheet) {
                if case .folder(let folder) = model.sidebarSelection, let info = model.library.projects[folder], model.searchText.isEmpty {
                    ProjectHeader(folder: folder, info: info)
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                        .padding(.vertical, 4)
                }
                ForEach(sheets) { sheet in
                    SheetRow(sheet: sheet)
                        .tag(sheet.url)
                        .draggable(sheet.url)
                        .contextMenu { SheetMenu(sheet: sheet) }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .overlay {
                if sheets.isEmpty {
                    ContentUnavailableView {
                        Label(model.searchText.isEmpty ? "No sheets yet" : "No matches", systemImage: model.searchText.isEmpty ? "square.and.pencil" : "magnifyingglass")
                    } description: {
                        Text(model.searchText.isEmpty ? "Every great story starts with a blank page." : "Try a different search.")
                    } actions: {
                        if model.searchText.isEmpty {
                            Button("New Sheet") { model.newSheet() }.buttonStyle(.glassProminent)
                        }
                    }
                }
            }
        }
    }
}

/// A quiet, rounded search field that sits under the title instead of in the toolbar.
private struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onExitCommand { text = ""; focused = false }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.primary.opacity(focused ? 0.08 : 0.05), in: .rect(cornerRadius: 9))
        .overlay {
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(.primary.opacity(focused ? 0.15 : 0.06))
        }
    }
}

private struct SheetRow: View {
    let sheet: Sheet

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(sheet.title)
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .lineLimit(1)
            if !sheet.preview.isEmpty {
                Text(sheet.preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 5) {
                Text(sheet.modified, format: .relative(presentation: .named))
                Text("·")
                Text("\(sheet.words.formatted()) words")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 1)
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
    }
}

private struct SheetMenu: View {
    @Environment(AppModel.self) private var model
    let sheet: Sheet

    var body: some View {
        if model.library.projects[sheet.folder]?.kind == .book, Chapters.number(of: sheet.url) != nil {
            Button("Move Chapter Up") { model.moveChapter(sheet.url, by: -1) }
            Button("Move Chapter Down") { model.moveChapter(sheet.url, by: 1) }
            Divider()
        }
        Button("Rename…") { model.beginRename(sheet.url) }
        Button("Duplicate") { model.duplicate(sheet.url) }
        Menu("Move To") {
            ForEach(Self.flatten(model.library.tree), id: \.node.url) { entry in
                Button(String(repeating: "    ", count: entry.depth) + entry.node.name) {
                    model.move(sheet.url, to: entry.node.url)
                }
                .disabled(entry.node.url == sheet.folder)
            }
        }
        Button("Show in Finder") { model.revealInFinder(sheet.url) }
        Divider()
        Button("Move to Trash", role: .destructive) { model.trash(sheet.url) }
    }

    private static func flatten(_ nodes: [FolderNode], depth: Int = 0) -> [(node: FolderNode, depth: Int)] {
        nodes.flatMap { [(node: $0, depth: depth)] + flatten($0.children ?? [], depth: depth + 1) }
    }
}

// MARK: Shared

/// The streak and today's progress, kept in the Library to keep the habit going.
struct StreakCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let streak = model.log.streak
        Button {
            model.showJourney = true
        } label: {
            HStack(spacing: 10) {
                // Today's plant grows as you write.
                PlantView(level: GardenArt.level(words: model.log.today, goal: model.prefs.dailyGoal), theme: model.prefs.theme, animated: false)
                    .frame(width: 34, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(streak > 0 ? "\(streak)-day streak" : "Plant a seed")
                        .font(.system(.callout, design: .serif).weight(.semibold))
                    Text("\(model.log.today.formatted()) / \(model.prefs.dailyGoal.formatted()) words today\(model.pomodoro.completedToday > 0 ? " · \(model.pomodoro.completedToday) 🍅" : "")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .themedGlass(in: .rect(cornerRadius: 14), interactive: true)
        .help("Open your Writing Garden (⌘⇧J)")
    }
}

/// Small-caps serif section titles for the sidebar.
struct SidebarHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .serif))
            .tracking(1.6)
            .foregroundStyle(.secondary)
    }
}

/// The tinted, translucent panel the navigator sits on, so the atmosphere shows through softly.
struct PanelBackground: View {
    @Environment(AppModel.self) private var model
    var opacity: Double

    var body: some View {
        let theme = model.prefs.theme
        ZStack {
            AtmosphereView(theme: theme, animated: false, continuous: true)
            theme.panelColor.opacity(1 - opacity * 0.35)
        }
        .ignoresSafeArea()
    }
}
