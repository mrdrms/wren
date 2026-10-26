import SwiftUI

/// The second editor, beside the page: notes, an outline or an earlier chapter to write
/// against. Drop another sheet on it to swap what it shows.
struct CompanionPane: View {
    @Environment(AppModel.self) private var model
    let sheet: CompanionSheet
    @State private var dropTargeted = false

    var body: some View {
        let theme = model.prefs.theme
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(sheet.title)
                        .font(.system(.callout, design: .serif).weight(.semibold))
                        .lineLimit(1)
                    Text("\(sheet.words.formatted()) words")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: 8)
                Menu {
                    Button("Swap Editors") { model.swapEditors() }
                    Button("Open in Main Editor") { model.openCompanionInMain() }
                    Divider()
                    Button("Show in Finder") { model.revealInFinder(sheet.url) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Swap, open in the main editor, or show in Finder")
                Button {
                    model.closeCompanion()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close the second editor (⌥⌘3)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) { Divider().opacity(0.6) }

            CompanionEditor(sheet: sheet, model: model)
                .id(ObjectIdentifier(sheet))
        }
        .background(theme.panelColor.opacity(theme.isDark ? 0.55 : 0.6))
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.accentColor, lineWidth: 2)
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first(where: { LibraryStore.markdownExtensions.contains($0.pathExtension.lowercased()) }) else { return false }
            model.openBeside(url)
            return true
        } isTargeted: { dropTargeted = $0 }
    }
}

/// A thin line you can drag to share the width between the two editors.
struct CompanionDivider: View {
    @Binding var fraction: Double
    let totalWidth: CGFloat
    @State private var start: Double?

    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(width: 1)
            .padding(.horizontal, 3)
            .contentShape(.rect)
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let origin = start ?? fraction
                        start = origin
                        fraction = min(0.65, max(0.25, origin - value.translation.width / max(1, totalWidth)))
                    }
                    .onEnded { _ in start = nil }
            )
            .ignoresSafeArea()
    }
}
