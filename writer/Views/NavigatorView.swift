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
                SettingsButton()
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
    /// ⌘-click and ⇧-click pick several sheets; a single pick opens it.
    @State private var selection: Set<URL> = []

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
                    SettingsButton()
                }
                .padding(.leading, -6)

                VStack(alignment: .leading, spacing: 2) {
                    Text(model.listTitle)
                        .font(.system(size: 26, weight: .medium, design: .serif))
                        .lineLimit(1)
                    Text("\(sheets.count) \(sheets.count == 1 ? "sheet" : "sheets") · \(sheets.reduce(0) { $0 + $1.words }.formatted()) words".uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }

                SearchField(text: $model.searchText)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 8)

            if selected(in: sheets).count > 1 {
                HStack {
                    Text("\(selected(in: sheets).count) selected").font(.callout.weight(.medium))
                    Spacer()
                    Button("Deselect") { selection = model.selectedSheet.map { [$0] } ?? [] }
                        .buttonStyle(.borderless)
                    Button(role: .destructive) {
                        model.trash(selected(in: sheets))
                    } label: {
                        Label("Move to Trash", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Move the selected sheets to the Trash (⌫)")
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 6)
                .transition(.opacity)
            }

            List(selection: $selection) {
                if case .folder(let folder) = model.sidebarSelection, let info = model.library.projects[folder], model.searchText.isEmpty {
                    ProjectHeader(folder: folder, info: info)
                        .listRowSeparator(.hidden)
                        .selectionDisabled()
                        .padding(.vertical, 4)
                }
                ForEach(Array(sheets.enumerated()), id: \.element.id) { index, sheet in
                    SheetRow(sheet: sheet, number: index + 1)
                        .tag(sheet.url)
                        .draggable(sheet.url)
                }
            }
            // Right-click acts on everything selected (or just the row you clicked).
            .contextMenu(forSelectionType: URL.self) { urls in
                let picked = sheets.filter { urls.contains($0.url) }
                if picked.count == 1, let sheet = picked.first {
                    SheetMenu(sheet: sheet)
                } else if picked.count > 1 {
                    MultiSheetMenu(sheets: picked)
                }
            }
            .onDeleteCommand { model.trash(selected(in: sheets)) }
            // Clicking empty space deselects; that mustn't close the sheet you're in, so only
            // a single pick opens anything.
            .onChange(of: selection) { _, picked in
                if picked.count == 1, let url = picked.first, url != model.selectedSheet { model.selectedSheet = url }
            }
            .onChange(of: model.selectedSheet, initial: true) { _, url in
                if let url, !selection.contains(url) { selection = [url] }
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

/// A sheet as an entry in a table of contents: its number, its title, a line of it,
/// and when and how long, set small like a running head.
private struct SheetRow: View {
    let sheet: Sheet
    let number: Int
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number < 10 ? "0\(number)" : "\(number)")
                .font(.system(size: 11, weight: .medium, design: .serif).monospacedDigit())
                .foregroundStyle(model.prefs.theme.accentColor.opacity(0.85))
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(sheet.title)
                    .font(.system(size: 15, weight: .semibold, design: .serif))
                    .lineLimit(1)
                if !sheet.preview.isEmpty {
                    Text(sheet.preview)
                        .font(.system(size: 12.5, design: .serif).italic())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 5) {
                    Text(sheet.modified, format: .relative(presentation: .named))
                    Text("·")
                    Text(sheet.words == 1 ? "1 word" : "\(sheet.words.formatted()) words")
                }
                .textCase(.uppercase)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 2)
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
        // The sheet in the main editor can't also open beside it, so it isn't offered there.
        if sheet.url != model.loadedURL {
            Button("Open Beside") { model.openBeside(sheet.url) }
            Divider()
        }
        Button("Rename…") { model.beginRename(sheet.url) }
        Button("Duplicate") { model.duplicate(sheet.url) }
        Menu("Move To") {
            ForEach(folderList(model.library.tree), id: \.node.url) { entry in
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

}

extension SheetsPage {
    /// The selection, limited to sheets still in the list and in list order.
    fileprivate func selected(in sheets: [Sheet]) -> [URL] {
        sheets.map(\.url).filter { selection.contains($0) }
    }
}

private struct MultiSheetMenu: View {
    @Environment(AppModel.self) private var model
    let sheets: [Sheet]

    var body: some View {
        Menu("Move \(sheets.count) Sheets To") {
            ForEach(folderList(model.library.tree), id: \.node.url) { entry in
                Button(String(repeating: "    ", count: entry.depth) + entry.node.name) {
                    model.move(sheets.map(\.url), to: entry.node.url)
                }
            }
        }
        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(sheets.map(\.url)) }
        Divider()
        Button("Move \(sheets.count) Sheets to Trash", role: .destructive) { model.trash(sheets.map(\.url)) }
    }
}

/// Every folder in the library, indented by depth, for "Move To" menus.
private func folderList(_ nodes: [FolderNode], depth: Int = 0) -> [(node: FolderNode, depth: Int)] {
    nodes.flatMap { [(node: $0, depth: depth)] + folderList($0.children ?? [], depth: depth + 1) }
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

/// Settings, a click away: themes, fonts, goals and the rest.
struct SettingsButton: View {
    var body: some View {
        SettingsLink {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.borderless)
        .help("Settings: themes, fonts, goals and more (⌘,)")
        .accessibilityLabel("Settings")
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
            AtmosphereView(theme: theme, animated: theme.atmosphere.drifts, continuous: true)
                .modifier(LightRest())
            // Glass themes let the light through the panel too.
            theme.panelColor.opacity(theme.atmosphere == .aurora ? 0.45 : 1 - opacity * 0.35)
        }
        .ignoresSafeArea()
    }
}
