import SwiftUI

private extension Color {
    init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

/// Pick what you're writing: a single sheet or a whole project.
struct TemplateGallery: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showProjects = false
    @State private var sheetChoice = Templates.chapter.id
    @State private var projectChoice = Templates.projects[0].id
    @State private var title = ""
    @State private var author = NSFullUserName()
    @State private var goal = 80_000

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("What are you writing?").font(.title2.weight(.bold))
                    Text("Templates come with gentle guidance in margin notes. They never show up in exports.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Kind", selection: $showProjects) {
                    Text("Single Sheet").tag(false)
                    Text("Project").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(20)

            Divider()

            HStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                        if showProjects {
                            ForEach(Templates.projects) { project in
                                card(name: project.name, symbol: project.symbol, tint: project.tint, summary: project.summary,
                                     selected: projectChoice == project.id) {
                                    projectChoice = project.id
                                    goal = project.goal ?? 0
                                }
                            }
                        } else {
                            ForEach(TemplateCategory.allCases, id: \.self) { category in
                                Section {
                                    ForEach(Templates.sheets.filter { $0.category == category }) { template in
                                        card(name: template.name, symbol: template.symbol, tint: template.tint, summary: template.summary,
                                             selected: sheetChoice == template.id) { sheetChoice = template.id }
                                    }
                                } header: {
                                    Text(category.rawValue)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, category == .general ? 0 : 8)
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(width: 520)

                Divider()

                details
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(20)
            }
        }
        .frame(width: 880, height: 580)
    }

    private func card(name: String, symbol: String, tint: UInt32, summary: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(Color(hex: tint).gradient, in: .rect(cornerRadius: 10))
                Text(name).font(.headline)
                Text(summary).font(.caption).foregroundStyle(.secondary).lineLimit(3)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(.background.secondary, in: .rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? model.prefs.theme.accentColor : Color.secondary.opacity(0.2), lineWidth: selected ? 2.5 : 1)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var details: some View {
        if showProjects, let project = Templates.projects.first(where: { $0.id == projectChoice }) {
            VStack(alignment: .leading, spacing: 14) {
                Label(project.name, systemImage: project.symbol).font(.title3.weight(.semibold))
                Text(project.summary).foregroundStyle(.secondary)
                TextField(project.kind == .book ? "Book title" : "Name", text: $title)
                    .textFieldStyle(.roundedBorder)
                if project.kind == .book {
                    TextField("Author", text: $author).textFieldStyle(.roundedBorder)
                    Stepper("Goal: \(goal.formatted()) words", value: $goal, in: 5_000...300_000, step: 5_000)
                }
                if !project.files.isEmpty {
                    Text("Includes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(project.files, id: \.path) { file in
                            Label(file.path.replacingOccurrences(of: ".md", with: ""), systemImage: file.path.contains("/") ? "note.text" : "doc.text")
                                .font(.callout)
                        }
                    }
                }
                Spacer()
                createButtons {
                    model.createProject(from: project, name: title, author: author, goal: project.kind == .book ? goal : nil)
                }
            }
        } else if let template = Templates.sheets.first(where: { $0.id == sheetChoice }) {
            VStack(alignment: .leading, spacing: 14) {
                Label(template.name, systemImage: template.symbol).font(.title3.weight(.semibold))
                if template.id != "journal" && template.id != "blank" {
                    TextField("Title", text: $title).textFieldStyle(.roundedBorder)
                }
                ScrollView {
                    Text(preview(template))
                        .font(.system(.callout, design: .serif))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .background(.background.secondary, in: .rect(cornerRadius: 10))
                createButtons {
                    model.createSheet(from: template, title: title)
                }
            }
        }
    }

    private func createButtons(_ create: @escaping () -> Void) -> some View {
        HStack {
            Spacer()
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Create") {
                dismiss()
                create()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.glassProminent)
        }
    }

    /// The template as it will read, with guidance notes shown as plain hints.
    private func preview(_ template: SheetTemplate) -> String {
        let rendered = Templates.render(template.body, title: title.isEmpty ? "Your title" : title)
        guard !rendered.isEmpty else { return "An empty page. Just you and your words." }
        return rendered
            .replacingOccurrences(of: "{>>", with: "💡 ")
            .replacingOccurrences(of: "<<}", with: "")
    }
}

/// Shown above the sheet list for project folders: progress, the right "new" button, and settings.
struct ProjectHeader: View {
    @Environment(AppModel.self) private var model
    let folder: URL
    let info: ProjectInfo

    var body: some View {
        let accent = model.prefs.theme.accentColor
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(info.kind.label, systemImage: info.kind.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                settingsMenu
            }
            if info.kind == .book {
                let words = model.projectWords(folder)
                let goal = info.goal ?? 80_000
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(words.formatted()).font(.system(.title2, design: .rounded).weight(.bold)).monospacedDigit()
                        Text("of \(goal.formatted()) words").foregroundStyle(.secondary)
                    }
                    ProgressView(value: min(1, Double(words) / Double(max(1, goal))))
                        .tint(accent)
                    Text("\(model.library.chapters(in: folder).count) chapters · about \(max(1, words / 275)) pages")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Button {
                    model.sidebarSelection = .folder(folder)
                    model.newSheet()
                } label: {
                    Label(info.kind.newItemLabel, systemImage: "plus")
                }
                .buttonStyle(.glassProminent)
                if info.kind == .book {
                    Button {
                        model.compileFolder = folder
                    } label: {
                        Label("Compile…", systemImage: "books.vertical")
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(12)
        .background(.background.secondary.opacity(0.6), in: .rect(cornerRadius: 14))
    }

    private var settingsMenu: some View {
        Menu {
            if info.kind == .book {
                Menu("Word Goal") {
                    ForEach([20_000, 50_000, 60_000, 80_000, 100_000, 120_000], id: \.self) { goal in
                        Button(goal.formatted()) { model.setProject(ProjectInfo(kind: info.kind, goal: goal, author: info.author), for: folder) }
                    }
                }
            }
            Menu("Project Type") {
                ForEach(ProjectKind.allCases, id: \.self) { kind in
                    Button(kind.label) { model.setProject(ProjectInfo(kind: kind, goal: info.goal ?? (kind == .book ? 80_000 : nil), author: info.author), for: folder) }
                }
            }
            Divider()
            Button("Make a Regular Folder") { model.setProject(nil, for: folder) }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Project settings")
    }
}

/// Options for turning a book's chapters into one manuscript.
struct CompileSheet: View {
    @Environment(AppModel.self) private var model
    let folder: URL
    @State private var format = Exporter.CompileFormat.pdf
    @State private var titlePage = true
    @State private var layout = BookSettings()
    @State private var book: BookTypesetter?
    @State private var chapterText: [String] = []

    var body: some View {
        let chapters = model.library.chapters(in: folder)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Label("Compile Book", systemImage: "books.vertical.fill").font(.title2.weight(.bold))
                Text("Joins every chapter, in order. Margin notes and struck text are left out.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Form {
                    Picker("Format", selection: $format) {
                        ForEach(Exporter.CompileFormat.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Title page", isOn: $titlePage)
                    if format == .pdf {
                        Section("Print layout") {
                            Picker("Page size", selection: $layout.trim) {
                                ForEach(TrimSize.allCases) { Text($0.label).tag($0) }
                            }
                            Toggle("Two-sided (mirrored margins)", isOn: $layout.twoSided)
                            Toggle("Chapters start on a right page", isOn: $layout.chaptersOnRight)
                                .disabled(!layout.twoSided)
                            Toggle("Page numbers", isOn: $layout.pageNumbers)
                            Toggle("Running heads", isOn: $layout.runningHeads)
                            Stepper("Text size: \(layout.fontSize.formatted()) pt", value: $layout.fontSize, in: 9...14, step: 0.5)
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, -20)

                Text("\(chapters.count) chapters · \(chapters.reduce(0) { $0 + $1.words }.formatted()) words\(book.map { " · \($0.pages.count) pages" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { model.compileFolder = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Compile…") {
                        model.compile(folder: folder, format: format, titlePage: titlePage, layout: layout)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(chapters.isEmpty)
                }
            }
            .padding(22)
            .frame(width: 340)

            Divider()

            Group {
                if format == .pdf, let book {
                    BookSpreadsView(book: book)
                } else if format == .pdf {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("No page preview", systemImage: "doc.text",
                                           description: Text("Pages only apply to the print-ready PDF. Word, web and Markdown reflow to fit."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(white: 0.5).opacity(0.12))
        }
        .frame(width: 1020, height: 680)
        .onAppear {
            if let saved = model.library.projects[folder]?.layout { layout = saved }
            chapterText = model.printableChapters(folder)
        }
        .task(id: TypesetKey(layout: layout, titlePage: titlePage, chapters: chapterText.count, format: format)) {
            // Let settings settle (stepper clicks, toggles) before laying out the whole book.
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, !chapterText.isEmpty, format == .pdf else { return }
            var settings = layout
            settings.titlePage = titlePage
            let info = model.library.projects[folder]
            book = BookTypesetter(title: model.bookTitle(folder), author: info?.author, chapters: chapterText, settings: settings)
        }
    }

    private struct TypesetKey: Equatable {
        let layout: BookSettings
        let titlePage: Bool
        let chapters: Int
        let format: Exporter.CompileFormat
    }
}

/// The book as it will print: two-page spreads, the first page alone on the right like a
/// real book.
struct BookSpreadsView: View {
    let book: BookTypesetter

    var body: some View {
        GeometryReader { proxy in
            let pageSize = book.pageSize
            // Two pages side by side, fitting the width with room to breathe.
            let pageWidth = min((proxy.size.width - 64) / 2, (proxy.size.height - 80) * pageSize.width / pageSize.height)
            let pageHeight = pageWidth * pageSize.height / pageSize.width
            ScrollView {
                LazyVStack(spacing: 28) {
                    ForEach(spreads.indices, id: \.self) { index in
                        let spread = spreads[index]
                        HStack(spacing: 0) {
                            pageView(spread.left, width: pageWidth, height: pageHeight, recto: false)
                            pageView(spread.right, width: pageWidth, height: pageHeight, recto: true)
                        }
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
                    }
                }
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
            .id(ObjectIdentifier(book))
        }
    }

    private var spreads: [(left: BookTypesetter.Page?, right: BookTypesetter.Page?)] {
        var result: [(BookTypesetter.Page?, BookTypesetter.Page?)] = []
        var pages = book.pages[...]
        // Page one is a right-hand page with nothing facing it.
        if let first = pages.first, first.isRecto {
            result.append((nil, first))
            pages = pages.dropFirst()
        }
        while !pages.isEmpty {
            let left = pages.popFirst()
            let right = pages.popFirst()
            result.append((left, right))
        }
        return result
    }

    @ViewBuilder
    private func pageView(_ page: BookTypesetter.Page?, width: CGFloat, height: CGFloat, recto: Bool) -> some View {
        if let page {
            Image(nsImage: book.image(of: page))
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: height)
                .overlay {
                    // A soft shadow along the spine, so a spread reads as an open book.
                    LinearGradient(colors: [.black.opacity(0.1), .clear], startPoint: recto ? .leading : .trailing,
                                   endPoint: recto ? UnitPoint(x: 0.08, y: 0.5) : UnitPoint(x: 0.92, y: 0.5))
                        .allowsHitTesting(false)
                }
        } else {
            Color.clear.frame(width: width, height: height)
        }
    }
}
