import SwiftUI

struct SheetListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let sheets = model.visibleSheets
        List(selection: $model.selectedSheet) {
            if case .folder(let folder) = model.sidebarSelection, let info = model.library.projects[folder], model.searchText.isEmpty {
                ProjectHeader(folder: folder, info: info)
                    .listRowSeparator(.hidden)
                    .selectionDisabled()
                    .padding(.vertical, 4)
            }
            ForEach(sheets) { sheet in
                SheetRow(sheet: sheet)
                    .draggable(sheet.url)
                    .contextMenu { menu(for: sheet) }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .background(PanelBackground(opacity: 0.3))
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
        .searchable(text: $model.searchText, placement: .sidebar, prompt: "Search sheets")
        .navigationTitle(model.listTitle)
        .navigationSubtitle("\(sheets.count) sheets · \(sheets.reduce(0) { $0 + $1.words }.formatted()) words")
        .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 400)
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Blank Sheet") { model.newSheet() }
                    Button("From Template…") { model.showTemplates = true }
                } label: {
                    Label("New Sheet", systemImage: "square.and.pencil")
                } primaryAction: {
                    model.newSheet()
                }
                .help("New sheet (⌘N). Hold for templates (⌥⌘N).")
            }
        }
    }

    @ViewBuilder
    private func menu(for sheet: Sheet) -> some View {
        if model.library.projects[sheet.folder]?.kind == .book, Chapters.number(of: sheet.url) != nil {
            Button("Move Chapter Up") { model.moveChapter(sheet.url, by: -1) }
            Button("Move Chapter Down") { model.moveChapter(sheet.url, by: 1) }
            Divider()
        }
        Button("Rename…") { model.beginRename(sheet.url) }
        Button("Duplicate") { model.duplicate(sheet.url) }
        Button("Show in Finder") { model.revealInFinder(sheet.url) }
        Divider()
        Button("Move to Trash", role: .destructive) { model.trash(sheet.url) }
    }
}

private struct SheetRow: View {
    let sheet: Sheet

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sheet.title)
                .font(.system(size: 14, weight: .semibold, design: .serif))
                .lineLimit(1)
            if !sheet.preview.isEmpty {
                Text(sheet.preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 6) {
                Text(sheet.modified, format: .relative(presentation: .named))
                Text("·")
                Text("\(sheet.words.formatted()) words")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}
