import SwiftUI

/// The sheet as a deck of section cards. Drag to restructure; the Markdown follows.
struct StoryboardView: View {
    @Environment(AppModel.self) private var model
    @State private var targeted: Int?

    var body: some View {
        let board = Storyboard.split(model.text)
        let maxWords = max(1, board.sections.map(\.words).max() ?? 1)
        let accent = model.prefs.theme.accentColor
        Group {
            if board.sections.count < 2 {
                ContentUnavailableView {
                    Label("No sections yet", systemImage: "square.grid.2x2")
                } description: {
                    Text("Add headings like **## Chapter One** and each section becomes a card you can drag into a new order.")
                } actions: {
                    Button("Back to Writing") { model.toggleBoard() }.buttonStyle(.glassProminent)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Storyboard").font(.system(.largeTitle, design: .serif).weight(.bold))
                            Text("\(board.sections.count) sections").foregroundStyle(.secondary)
                            Spacer()
                            Text("Drag to reorder · Double-click to write").font(.callout).foregroundStyle(.secondary)
                        }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 18)], spacing: 18) {
                            ForEach(Array(board.sections.enumerated()), id: \.element.id) { index, section in
                                card(section, number: index + 1, maxWords: maxWords, accent: accent)
                            }
                        }
                    }
                    .padding(32)
                    .padding(.top, 30)
                }
            }
        }
        .animation(.spring(duration: 0.4, bounce: 0.2), value: board)
    }

    private func card(_ section: StorySection, number: Int, maxWords: Int, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(number)")
                    .font(.system(.callout, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(accent, in: .circle)
                Spacer()
                Text("\(section.words.formatted()) words").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Text(section.title.isEmpty ? "Untitled section" : section.title)
                .font(.system(.title3, design: .serif).weight(.semibold))
                .lineLimit(2)
            Text(section.synopsis.isEmpty ? "Nothing here yet…" : section.synopsis)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(5)
            Spacer(minLength: 0)
            // Pacing: how long this section runs compared with the longest one.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(accent.opacity(0.15))
                    Capsule().fill(accent).frame(width: max(6, geo.size.width * Double(section.words) / Double(maxWords)))
                }
            }
            .frame(height: 5)
            .help("Section length relative to the longest section")
        }
        .padding(16)
        .frame(height: 220)
        .themedGlass(in: .rect(cornerRadius: 20), interactive: true)
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(accent, lineWidth: targeted == section.id ? 3 : 0)
        }
        .scaleEffect(targeted == section.id ? 1.03 : 1)
        .animation(.snappy, value: targeted)
        .contentShape(.rect)
        .onTapGesture(count: 2) { model.openSection(section) }
        .draggable(String(section.id)) {
            Text(section.title).font(.headline).padding(10).background(.regularMaterial, in: .rect(cornerRadius: 10))
        }
        .dropDestination(for: String.self) { items, _ in
            guard let from = items.first.flatMap(Int.init) else { return false }
            model.moveSection(from: from, to: section.id)
            return true
        } isTargeted: { isTargeted in
            targeted = isTargeted ? section.id : (targeted == section.id ? nil : targeted)
        }
    }
}
