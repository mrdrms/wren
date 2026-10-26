import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        List(selection: $model.sidebarSelection) {
            Section {
                Label("All Sheets", systemImage: "doc.text").tag(SidebarSelection.all)
                Label("Recent", systemImage: "clock").tag(SidebarSelection.recent)
            } header: {
                SidebarHeader("Writing")
            }
            Section {
                OutlineGroup(model.library.tree, children: \.children) { node in
                    Label(node.name, systemImage: node.kind?.symbol ?? (node.isRoot ? "books.vertical" : "folder"))
                        .tag(SidebarSelection.folder(node.url))
                        .dropDestination(for: URL.self) { urls, _ in
                            urls.forEach { model.move($0, to: node.url) }
                            return !urls.isEmpty
                        }
                        .contextMenu { folderMenu(node) }
                }
            } header: {
                SidebarHeader("Folders")
            }
        }
        .scrollContentBackground(.hidden)
        .background(PanelBackground(opacity: 0.5))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                StreakCard()
                Button {
                    model.showTemplates = true
                } label: {
                    Label("Start a Project…", systemImage: "sparkles")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                Button {
                    model.addFolder()
                } label: {
                    Label("Add Folder…", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
            }
            .padding(12)
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
    }

    @ViewBuilder
    private func folderMenu(_ node: FolderNode) -> some View {
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

/// The streak and today's progress, always in view to keep the habit going.
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

/// The tinted, translucent panel the sidebar and sheet list sit on, so the atmosphere
/// shows through softly.
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
