import SwiftUI

// MARK: - Shared button

private struct FormatButton: View {
    let symbol: String
    let help: String
    var active = false
    let action: () -> Void
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    var body: some View {
        let accent = model.prefs.theme.accentColor
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: active ? .bold : .medium))
                .frame(width: 28, height: 26)
                .foregroundStyle(active ? accent : Color.primary.opacity(hovering ? 1 : 0.78))
                .background(active ? accent.opacity(0.16) : Color.primary.opacity(hovering ? 0.07 : 0), in: .rect(cornerRadius: 7))
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .help(help)
    }
}

// MARK: - Format bar

/// Word-processor style formatting for people who have never typed Markdown.
struct FormatBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.formatState
        HStack(spacing: 2) {
            Menu {
                Button("Title") { model.format(.heading(1)) }
                Button("Heading") { model.format(.heading(2)) }
                Button("Subheading") { model.format(.heading(3)) }
                Divider()
                Button("Body") { model.format(.paragraph) }
                Button("Quote") { model.format(.quote) }
            } label: {
                HStack(spacing: 4) {
                    Text(blockLabel(state.block))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 12, weight: .medium))
                .frame(width: 84)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .fixedSize()
            .padding(.horizontal, 6)
            .help("Paragraph style")

            Divider().frame(height: 16).padding(.horizontal, 4)

            FormatButton(symbol: "bold", help: "Bold (⌘B)", active: state.bold) { model.format(.bold) }
            FormatButton(symbol: "italic", help: "Italic (⌘I)", active: state.italic) { model.format(.italic) }
            FormatButton(symbol: "strikethrough", help: "Strikethrough (⇧⌘X)", active: state.strike) { model.format(.strikethrough) }
            FormatButton(symbol: "highlighter", help: "Highlight (⇧⌘H)", active: state.highlight) { model.format(.highlight) }
            FormatButton(symbol: "link", help: "Link (⌘L)", active: state.link) { model.format(.link) }

            Divider().frame(height: 16).padding(.horizontal, 4)

            FormatButton(symbol: "list.bullet", help: "Bulleted list (⇧⌘8)", active: state.block == .bullet) { model.format(.bullet) }
            FormatButton(symbol: "list.number", help: "Numbered list (⇧⌘7)", active: state.block == .numbered) { model.format(.numbered) }
            FormatButton(symbol: "checklist", help: "Checklist (⇧⌘9)", active: state.block == .task) { model.format(.task) }
            FormatButton(symbol: "text.quote", help: "Quote (⌘')", active: state.block == .quote) { model.format(.quote) }

            Divider().frame(height: 16).padding(.horizontal, 4)

            InsertMenu()

            FormatButton(symbol: "textformat", help: model.prefs.liveFormatting
                         ? "Live formatting is on: headings and bold are shown styled. Click for plain Markdown."
                         : "Plain Markdown. Click to see formatting in the editor as you type.",
                         active: model.prefs.liveFormatting) {
                model.prefs.liveFormatting.toggle()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .themedGlass(in: .capsule)
    }

    private func blockLabel(_ block: BlockKind) -> String {
        switch block {
        case .title, .heading, .subheading, .quote: block.label
        default: "Body"
        }
    }
}

/// Everything you can add to a post, in one place.
struct InsertMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            ForEach(SlashCatalog.insertables) { item in
                Button { item.run(model) } label: { Label(item.title, systemImage: item.symbol) }
            }
        } label: {
            Label("Insert", systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .padding(.horizontal, 6)
        .help("Insert an image, video, divider and more. Tip: type / on an empty line.")
    }
}

// MARK: - Selection bubble

/// Pops up over selected text, like Medium's editor.
struct SelectionBubble: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let state = model.formatState
        HStack(spacing: 2) {
            FormatButton(symbol: "bold", help: "Bold", active: state.bold) { model.format(.bold) }
            FormatButton(symbol: "italic", help: "Italic", active: state.italic) { model.format(.italic) }
            FormatButton(symbol: "strikethrough", help: "Strikethrough", active: state.strike) { model.format(.strikethrough) }
            FormatButton(symbol: "highlighter", help: "Highlight", active: state.highlight) { model.format(.highlight) }
            FormatButton(symbol: "link", help: "Link", active: state.link) { model.format(.link) }
            Divider().frame(height: 16).padding(.horizontal, 3)
            FormatButton(symbol: "textformat.size.larger", help: "Heading", active: state.block == .heading) { model.format(.heading(2)) }
            FormatButton(symbol: "text.quote", help: "Quote", active: state.block == .quote) { model.format(.quote) }
            FormatButton(symbol: "text.bubble", help: "Add a margin note") { model.format(.note) }
        }
        .padding(5)
        .themedGlass(in: .capsule)
        .fixedSize()
    }
}

// MARK: - Slash menu

struct SlashItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbol: String
    let keywords: String
    let run: (AppModel) -> Void
}

enum SlashCatalog {
    static let all: [SlashItem] = [
        SlashItem(id: "text", title: "Text", subtitle: "A plain paragraph", symbol: "text.alignleft", keywords: "body paragraph normal plain") { $0.format(.paragraph) },
        SlashItem(id: "h1", title: "Title", subtitle: "Big heading", symbol: "textformat.size.larger", keywords: "heading h1 title") { $0.format(.heading(1)) },
        SlashItem(id: "h2", title: "Heading", subtitle: "Section heading", symbol: "textformat.size", keywords: "heading h2 section") { $0.format(.heading(2)) },
        SlashItem(id: "h3", title: "Subheading", subtitle: "Smaller heading", symbol: "textformat.size.smaller", keywords: "heading h3 subheading") { $0.format(.heading(3)) },
        SlashItem(id: "bullet", title: "Bulleted list", subtitle: "A simple list", symbol: "list.bullet", keywords: "list bullet ul points") { $0.format(.bullet) },
        SlashItem(id: "numbered", title: "Numbered list", subtitle: "Steps in order", symbol: "list.number", keywords: "list numbered ordered ol steps 1") { $0.format(.numbered) },
        SlashItem(id: "task", title: "Checklist", subtitle: "Things to tick off", symbol: "checklist", keywords: "todo task check checkbox") { $0.format(.task) },
        SlashItem(id: "quote", title: "Quote", subtitle: "Pull out a quotation", symbol: "text.quote", keywords: "quote blockquote citation") { $0.format(.quote) },
        SlashItem(id: "image", title: "Image or video", subtitle: "From your Mac", symbol: "photo.on.rectangle", keywords: "image picture photo video media upload file") { $0.insertMediaWithPanel() },
        SlashItem(id: "youtube", title: "YouTube video", subtitle: "Embed by link", symbol: "play.rectangle", keywords: "youtube video embed") { $0.beginVideoEmbed() },
        SlashItem(id: "link", title: "Link", subtitle: "Link to a web page", symbol: "link", keywords: "link url web") { $0.beginLink() },
        SlashItem(id: "divider", title: "Divider", subtitle: "A break between sections", symbol: "minus", keywords: "divider line separator rule hr break") { $0.format(.divider) },
        SlashItem(id: "code", title: "Code block", subtitle: "For code snippets", symbol: "chevron.left.forwardslash.chevron.right", keywords: "code snippet programming") { $0.format(.codeBlock) },
        SlashItem(id: "note", title: "Margin note", subtitle: "A private note to yourself", symbol: "text.bubble", keywords: "note comment reminder") { $0.format(.note) },
        SlashItem(id: "post", title: "Post details", subtitle: "Title and date for your blog", symbol: "doc.badge.gearshape", keywords: "post details front matter blog title date meta") { $0.insertPostDetails() },
    ]

    static var insertables: [SlashItem] {
        let ids = ["image", "youtube", "link", "divider", "code", "note", "post"]
        return ids.compactMap { id in all.first { $0.id == id } }
    }

    static func filter(_ query: String) -> [SlashItem] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        let starts = all.filter { $0.title.lowercased().hasPrefix(q) }
        let rest = all.filter { item in
            !item.title.lowercased().hasPrefix(q) && (item.title.lowercased().contains(q) || item.keywords.split(separator: " ").contains { $0.hasPrefix(q) })
        }
        return starts + rest
    }
}

@Observable
final class SlashMenuState {
    var items: [SlashItem] = SlashCatalog.all
    var selected = 0
}

struct SlashMenuView: View {
    let state: SlashMenuState
    let choose: (Int) -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let accent = model.prefs.theme.accentColor
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Insert").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.horizontal, 10).padding(.top, 6)
                    ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in
                        let selected = index == state.selected
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol)
                                .foregroundStyle(selected ? accent : Color.secondary)
                                .frame(width: 30, height: 30)
                                .background(selected ? accent.opacity(0.14) : Color.primary.opacity(0.06), in: .rect(cornerRadius: 7))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.system(size: 13, weight: .medium))
                                Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .foregroundStyle(Color.primary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(selected ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 9))
                        .contentShape(.rect)
                        .id(index)
                        .onTapGesture { choose(index) }
                        .onHover { if $0 { state.selected = index } }
                    }
                }
                .padding(6)
            }
            .onChange(of: state.selected) { proxy.scrollTo(state.selected) }
        }
        .frame(width: 290)
        .background(.regularMaterial, in: .rect(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

// MARK: - Link sheet

struct LinkSheet: View {
    @Environment(AppModel.self) private var model
    @State var draft: LinkDraft
    @FocusState private var focus: Field?

    private enum Field { case text, url }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(draft.kind == .link ? (draft.isEditing ? "Edit Link" : "Add Link") : "Embed a YouTube Video",
                  systemImage: draft.kind == .link ? "link" : "play.rectangle")
                .font(.title3.weight(.semibold))
            if draft.kind == .link {
                LabeledContent("Text") {
                    TextField("What readers will click", text: $draft.text)
                        .textFieldStyle(.roundedBorder)
                        .focused($focus, equals: .text)
                }
            }
            LabeledContent(draft.kind == .link ? "Address" : "Video link") {
                TextField(draft.kind == .link ? "example.com" : "https://www.youtube.com/watch?v=…", text: $draft.url)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .url)
                    .onSubmit { model.applyLink(draft) }
            }
            if draft.kind == .video {
                LabeledContent("Caption") {
                    TextField("Optional", text: $draft.text).textFieldStyle(.roundedBorder)
                }
            }
            HStack {
                if draft.isEditing {
                    Button("Remove Link", role: .destructive) { model.removeLink(draft) }
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.linkDraft = nil }
                    .keyboardShortcut(.cancelAction)
                Button(draft.isEditing ? "Update" : (draft.kind == .link ? "Add Link" : "Embed")) { model.applyLink(draft) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(draft.url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440)
        .onAppear { focus = draft.kind == .link && draft.text.isEmpty ? .text : .url }
    }
}
