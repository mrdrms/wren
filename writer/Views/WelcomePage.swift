import SwiftUI

/// Wren's home: where a session begins. A greeting, the sheet you were writing waiting to be
/// picked up, ways to start something new, your recent pages laid out like manuscripts on a
/// desk, and a short walkthrough. Opening any sheet goes straight to it.
struct WelcomePage: View {
    @Environment(AppModel.self) private var model
    @AppStorage("walkthroughDone") private var walkthroughDone = ""
    @State private var appeared = false

    var body: some View {
        let theme = model.prefs.theme
        ScrollView {
            VStack(alignment: .leading, spacing: 34) {
                header
                    .entrance(appeared, delay: 0)

                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 22) {
                        if let current = currentSheet {
                            ContinueCard(sheet: current) { open(current.url) }
                        } else {
                            StartCard(hasSheets: !model.library.sheets.isEmpty) {
                                model.showWelcome = false
                                model.newSheet()
                            }
                        }
                        actions
                    }
                    .frame(maxWidth: .infinity)
                    walkthrough
                        .frame(width: 300)
                }
                .entrance(appeared, delay: 0.08)

                if !recentSheets.isEmpty {
                    gallery
                        .entrance(appeared, delay: 0.16)
                }
                if !projects.isEmpty {
                    projectList
                        .entrance(appeared, delay: 0.22)
                }

                Toggle("Show this page when Wren opens", isOn: Bindable(model.prefs).showWelcome)
                    .toggleStyle(.checkbox)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .entrance(appeared, delay: 0.26)
            }
            .padding(.horizontal, 52)
            .padding(.top, 40)
            .padding(.bottom, 48)
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg.opacity(theme.atmosphere == .none ? 0 : 0.3).ignoresSafeArea())
        .onAppear { withAnimation(.smooth(duration: 0.7)) { appeared = true } }
        .task {
            // The page has no text to type into; give the keyboard back so ↩ continues writing.
            try? await Task.sleep(for: .milliseconds(150))
            if NSApp.keyWindow?.firstResponder is NSText { NSApp.keyWindow?.makeFirstResponder(nil) }
        }
    }

    // MARK: Greeting

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .tracking(2.2)
                .foregroundStyle(.secondary)
            Text(greeting)
                .font(.system(size: 50, weight: .regular, design: .serif))
                .tracking(-0.5)
            HStack(spacing: 10) {
                StatChip(symbol: "pencil.line", text: "\(model.log.today.formatted()) of \(model.prefs.dailyGoal.formatted()) words today")
                    .help("Words written today toward your daily goal. Change the goal in the inspector.")
                if model.log.streak > 0 {
                    StatChip(symbol: "flame", text: model.log.streak == 1 ? "1-day streak" : "\(model.log.streak)-day streak")
                        .help("Days in a row you've written something")
                }
                if !model.library.sheets.isEmpty {
                    StatChip(symbol: "doc.text", text: model.library.sheets.count == 1 ? "1 sheet" : "\(model.library.sheets.count.formatted()) sheets")
                        .help("Sheets in your library")
                }
            }
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        switch hour {
        case 0..<5: return "Writing late tonight."
        case 5..<12: return "Good morning."
        case 12..<18: return "Good afternoon."
        default: return "Good evening."
        }
    }

    // MARK: Start

    private var currentSheet: Sheet? {
        guard let url = model.loadedURL else { return nil }
        return model.library.sheets.first { $0.url == url }
    }

    private var actions: some View {
        HStack(spacing: 14) {
            ActionTile(symbol: "square.and.pencil", title: "New Sheet", shortcut: "⌘N") {
                model.showWelcome = false
                model.newSheet()
            }
            .help("Start a blank sheet")
            ActionTile(symbol: "rectangle.stack", title: "From a Template", shortcut: "⌥⌘N") { model.showTemplates = true }
                .help("Start from a template: essays, blog posts, chapters, journal entries and more")
            ActionTile(symbol: "scribble.variable", title: "New Sketch", shortcut: nil) { model.newSketchSheet() }
                .help("Draw with pen, brush or marker. The drawing becomes a new sheet of its own.")
            ActionTile(symbol: "folder", title: "Open a Folder", shortcut: "⌘O") { model.addFolder() }
                .help("Work on a folder of Markdown (.md) files anywhere on your Mac. Wren edits them in place.")
        }
    }

    // MARK: Recent

    private var recentSheets: [Sheet] {
        Array(model.library.sheets.filter { $0.url != model.loadedURL }.sorted { $0.modified > $1.modified }.prefix(8))
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Recent")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 18, alignment: .top)], alignment: .leading, spacing: 20) {
                ForEach(recentSheets) { sheet in
                    PageCard(sheet: sheet) { open(sheet.url) }
                }
            }
        }
    }

    // MARK: Projects

    private var projects: [(url: URL, info: ProjectInfo)] {
        model.library.projects.map { ($0.key, $0.value) }.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("Projects")
            HStack(spacing: 14) {
                ForEach(projects, id: \.url) { project in
                    let words = model.library.sheets.filter { $0.url.path.hasPrefix(project.url.path + "/") }.reduce(0) { $0 + $1.words }
                    Button { openProject(project.url) } label: {
                        HStack(spacing: 12) {
                            ZStack {
                                if let goal = project.info.goal, goal > 0 {
                                    GoalRing(progress: min(1, Double(words) / Double(goal)), lineWidth: 3, tint: model.prefs.theme.accentColor)
                                }
                                Image(systemName: project.info.kind.symbol).font(.system(size: 13))
                            }
                            .frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.url.lastPathComponent).font(.system(size: 14, weight: .semibold, design: .serif))
                                Text("\(project.info.kind.label) · \(words.formatted()) words")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .themedGlass(in: .rect(cornerRadius: 14), interactive: true)
                    .help("Open the \(project.info.kind.label.lowercased()) “\(project.url.lastPathComponent)”")
                }
            }
        }
    }

    // MARK: Walkthrough

    private struct Step: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let tip: String
        let action: (AppModel) -> Void
    }

    private var steps: [Step] {
        [
            Step(id: "write", symbol: "pencil.line", title: "Write your first words", tip: "Open a new sheet and start typing. Everything saves as you go.") { m in
                m.showWelcome = false
                m.newSheet()
            },
            Step(id: "theme", symbol: "paintpalette", title: "Choose an atmosphere", tip: "Pick a theme in Settings → Appearance: Aurora, Dawn, Paper, Terminal and more.") { _ in
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            Step(id: "draw", symbol: "scribble.variable", title: "Make a sketch", tip: "Draw something; it becomes a new sheet. Inside any sheet, type / and choose Drawing to add one there.") { m in
                m.newSketchSheet()
            },
            Step(id: "goal", symbol: "target", title: "Set a daily goal", tip: "Open the goals panel to set how many words you aim for each day.") { m in
                m.showWelcome = false
                m.inspectorTab = .goals
                m.showInspector = true
            },
            Step(id: "zen", symbol: "moon.stars", title: "Write in Zen mode", tip: "Hide everything but the page. Press Esc to bring it all back.") { m in
                m.showWelcome = false
                m.toggleZen()
            },
        ]
    }

    private var done: Set<String> { Set(walkthroughDone.split(separator: ",").map(String.init)) }

    private var walkthrough: some View {
        let accent = model.prefs.theme.accentColor
        let finished = steps.filter { done.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                GoalRing(progress: Double(finished) / Double(steps.count), lineWidth: 3.5, tint: accent)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Get started").font(.system(size: 15, weight: .semibold, design: .serif))
                    Text("\(finished) of \(steps.count) done").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 2) {
                ForEach(steps) { step in
                    let complete = done.contains(step.id)
                    Button {
                        markDone(step.id)
                        step.action(model)
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: complete ? "checkmark.circle.fill" : step.symbol)
                                .font(.system(size: 14))
                                .foregroundStyle(complete ? accent : Color.secondary)
                                .frame(width: 20)
                            Text(step.title)
                                .font(.system(size: 13, weight: .medium))
                                .strikethrough(complete, color: .secondary)
                                .foregroundStyle(complete ? .secondary : .primary)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .contentShape(.rect)
                    }
                    .buttonStyle(HoverHighlight())
                    .help(step.tip)
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .themedGlass(in: .rect(cornerRadius: 20))
    }

    private func markDone(_ id: String) {
        var set = done
        set.insert(id)
        walkthroughDone = set.sorted().joined(separator: ",")
    }

    // MARK: Opening

    private func open(_ url: URL) {
        model.searchText = ""
        if !model.library.sheets(for: model.sidebarSelection, search: "").contains(where: { $0.url == url }) {
            model.sidebarSelection = .all
        }
        model.navigatorPage = .sheets
        model.selectedSheet = url
        model.showWelcome = false
    }

    private func openProject(_ folder: URL) {
        model.sidebarSelection = .folder(folder)
        model.navigatorPage = .sheets
        if let first = model.library.sheets(for: .folder(folder), search: "").first {
            model.selectedSheet = first.url
        }
        model.showWelcome = false
    }
}

// MARK: - Pieces

/// The sheet you were last writing, waiting where you left it.
private struct ContinueCard: View {
    @Environment(AppModel.self) private var model
    let sheet: Sheet
    let action: () -> Void

    var body: some View {
        let theme = model.prefs.theme
        Button(action: action) {
            HStack(alignment: .top, spacing: 20) {
                // A small sheet of the page itself.
                VStack(alignment: .leading, spacing: 5) {
                    Text(sheet.title)
                        .font(.system(size: 9, weight: .bold, design: .serif))
                        .lineLimit(2)
                    Text(sheet.preview)
                        .font(.system(size: 6.5, design: .serif))
                        .lineSpacing(1.5)
                        .foregroundStyle(.secondary)
                        .lineLimit(9)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .frame(width: 92, height: 120, alignment: .topLeading)
                .background(theme.paperColor, in: .rect(cornerRadius: 4))
                .foregroundStyle(theme.fg)
                .shadow(color: .black.opacity(theme.isDark ? 0.5 : 0.14), radius: 8, y: 4)
                .rotationEffect(.degrees(-2))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Continue writing")
                        .font(.system(size: 10.5, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1.6)
                        .foregroundStyle(theme.accentColor)
                    Text(sheet.title)
                        .font(.system(size: 26, weight: .medium, design: .serif))
                        .lineLimit(2)
                    if !sheet.preview.isEmpty {
                        Text(sheet.preview)
                            .font(.system(size: 13.5, design: .serif).italic())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    HStack(spacing: 12) {
                        Label("Continue", systemImage: "arrow.right")
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(theme.accentColor, in: .capsule)
                            .foregroundStyle(theme.isDark ? Color.black : Color.white)
                        Text("\(sheet.words.formatted()) words · \(sheet.modified.formatted(.relative(presentation: .named)))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .help("Pick up where you left off (↩)")
        .themedGlass(in: .rect(cornerRadius: 22), interactive: true)
    }
}

/// When there's nothing to pick up: an invitation to begin.
private struct StartCard: View {
    @Environment(AppModel.self) private var model
    let hasSheets: Bool
    let action: () -> Void

    var body: some View {
        let theme = model.prefs.theme
        HStack(spacing: 22) {
            Enso(color: theme.fg.opacity(0.85))
                .frame(width: 96, height: 96)
            VStack(alignment: .leading, spacing: 8) {
                Text(hasSheets ? "Pick up a page" : "A blank page")
                    .font(.system(size: 10.5, weight: .semibold))
                    .textCase(.uppercase)
                    .tracking(1.6)
                    .foregroundStyle(theme.accentColor)
                Text(hasSheets ? "Choose a recent sheet below, or start something new." : "Every story starts with a blank page.")
                    .font(.system(size: 24, weight: .medium, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: action) {
                    Label("New Sheet", systemImage: "square.and.pencil")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(theme.accentColor, in: .capsule)
                        .foregroundStyle(theme.isDark ? Color.black : Color.white)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .help("Start a blank sheet (↩)")
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(22)
        .themedGlass(in: .rect(cornerRadius: 22))
    }
}

/// A recent sheet as a page on the desk: its title and opening lines, on paper.
private struct PageCard: View {
    @Environment(AppModel.self) private var model
    let sheet: Sheet
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let theme = model.prefs.theme
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(sheet.title)
                        .font(.system(size: 14, weight: .semibold, design: .serif))
                        .lineLimit(2)
                    Text(sheet.preview.isEmpty ? " " : sheet.preview)
                        .font(.system(size: 10.5, design: .serif))
                        .lineSpacing(2)
                        .foregroundStyle(theme.fg.opacity(0.62))
                        .lineLimit(6)
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, minHeight: 168, maxHeight: 168, alignment: .topLeading)
                .background(theme.paperColor, in: .rect(cornerRadius: 6))
                .foregroundStyle(theme.fg)
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(theme.fg.opacity(0.06)))
                .shadow(color: .black.opacity(theme.isDark ? (hovering ? 0.6 : 0.45) : (hovering ? 0.18 : 0.1)),
                        radius: hovering ? 16 : 8, y: hovering ? 8 : 4)
                .offset(y: hovering ? -4 : 0)

                VStack(alignment: .leading, spacing: 2) {
                    Text(sheet.folder.lastPathComponent)
                        .font(.system(size: 9.5, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(1)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("\(sheet.modified.formatted(.relative(presentation: .named))) · \(sheet.words == 1 ? "1 word" : "\(sheet.words.formatted()) words")")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 2)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.spring(duration: 0.3, bounce: 0.2), value: hovering)
        .help("Open “\(sheet.title)”")
    }
}

/// A large glass tile for starting something.
private struct ActionTile: View {
    @Environment(AppModel.self) private var model
    @Environment(\.isEnabled) private var enabled
    let symbol: String
    let title: String
    let shortcut: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .regular))
                    .foregroundStyle(model.prefs.theme.accentColor)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 13.5, weight: .semibold))
                    Text(shortcut ?? " ")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.45)
        .themedGlass(in: .rect(cornerRadius: 18), interactive: true)
    }
}

private struct StatChip: View {
    let symbol: String
    let text: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.06), in: .capsule)
    }
}

private struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.8)
            .foregroundStyle(.secondary)
    }
}

private struct HoverHighlight: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.1 : hovering ? 0.06 : 0), in: .rect(cornerRadius: 10))
            .onHover { hovering = $0 }
    }
}

private extension View {
    /// Rises gently into place as the page opens, each part a beat after the last.
    func entrance(_ shown: Bool, delay: Double) -> some View {
        opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(.smooth(duration: 0.6).delay(delay), value: shown)
    }
}
