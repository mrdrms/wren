import AppKit
import SwiftUI

struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("Inspector", selection: $model.inspectorTab) {
                ForEach(InspectorTab.allCases) { tab in
                    Image(systemName: tab.symbol).help(tab.label).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(12)

            ScrollView {
                Group {
                    switch model.inspectorTab {
                    case .goals: GoalsPane()
                    case .outline: OutlinePane()
                    case .style: StylePane()
                    case .stats: StatsPane()
                    case .history: HistoryPane()
                    case .cuts: CuttingRoomPane()
                    case .ai: AIPane()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .inspectorColumnWidth(min: 250, ideal: 290, max: 380)
    }
}

private struct PaneTitle: View {
    let title: String
    var body: some View {
        Text(title).font(.title3.weight(.semibold)).padding(.bottom, 2)
    }
}

private struct GoalsPane: View {
    @Environment(AppModel.self) private var model
    @State private var customGoal = ""

    var body: some View {
        let accent = model.prefs.theme.accentColor
        VStack(alignment: .leading, spacing: 18) {
            PaneTitle(title: "This sheet")
            HStack(spacing: 16) {
                GoalRing(progress: model.documentProgress ?? 0, lineWidth: 8, tint: accent)
                    .frame(width: 76, height: 76)
                    .overlay {
                        if (model.documentProgress ?? 0) < 1 {
                            Text(model.documentGoal == nil ? "—" : "\(Int((model.documentProgress ?? 0) * 100))%")
                                .font(.system(.headline, design: .rounded))
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.stats.words.formatted()) words").font(.headline)
                    if let goal = model.documentGoal {
                        Text(goal > model.stats.words ? "\((goal - model.stats.words).formatted()) to go" : "Goal reached 🎉")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No goal set").foregroundStyle(.secondary)
                    }
                }
            }
            HStack {
                ForEach([500, 1000, 2500, 5000], id: \.self) { goal in
                    Button(goal >= 1000 ? "\(goal / 1000)k" : "\(goal)") { model.setDocumentGoal(goal) }
                        .buttonStyle(.glass)
                        .tint(model.documentGoal == goal ? accent : nil)
                }
            }
            HStack {
                TextField("Custom goal", text: $customGoal)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(applyCustom)
                Button("Set", action: applyCustom)
                if model.documentGoal != nil {
                    Button("Clear") { model.setDocumentGoal(nil) }
                }
            }

            Divider()
            PaneTitle(title: "Today")
            HStack(spacing: 16) {
                GoalRing(progress: model.dailyProgress, lineWidth: 8, tint: .orange)
                    .frame(width: 76, height: 76)
                    .overlay { Text("🔥").font(.title2).opacity(model.dailyProgress >= 1 ? 0 : 1) }
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(model.log.today.formatted()) / \(model.prefs.dailyGoal.formatted())").font(.headline)
                    Text(model.log.streak > 0 ? "\(model.log.streak)-day streak" : "Write today to start a streak")
                        .foregroundStyle(.secondary)
                }
            }
            Stepper("Daily goal: \(model.prefs.dailyGoal.formatted())", value: Bindable(model.prefs).dailyGoal, in: 50...20_000, step: 50)

            Divider()
            PaneTitle(title: "Writing sprint")
            if model.sprint != nil {
                HStack {
                    Text("\(model.sprintWords) words so far").foregroundStyle(.secondary)
                    Spacer()
                    Button("Finish") { model.finishSprint() }
                }
            } else {
                Text("Race the clock. No editing, no second-guessing, just words.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack {
                    ForEach([5, 15, 25, 45], id: \.self) { minutes in
                        Button("\(minutes)m") { model.startSprint(minutes: minutes) }
                            .buttonStyle(.glass)
                            .tint(nil)
                    }
                }
            }
        }
    }

    private func applyCustom() {
        if let value = Int(customGoal.filter(\.isNumber)), value > 0 {
            model.setDocumentGoal(value)
            customGoal = ""
        }
    }
}

private struct OutlinePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            PaneTitle(title: "Outline")
            if model.headings.isEmpty {
                Text("Add headings with # to build an outline you can jump around in.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(model.headings) { heading in
                Button {
                    model.jump(to: heading)
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(model.prefs.theme.accentColor.opacity(1 - Double(heading.level - 1) * 0.2))
                            .frame(width: 6, height: 6)
                        Text(heading.title)
                            .font(heading.level == 1 ? .headline : .body)
                            .lineLimit(1)
                    }
                    .padding(.leading, CGFloat(heading.level - 1) * 14)
                    .padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }

            if !model.notes.isEmpty {
                Divider().padding(.vertical, 8)
                PaneTitle(title: "Notes & TKs")
                ForEach(model.notes) { note in
                    Button {
                        model.jump(to: note)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: note.kind == .tk ? "exclamationmark.circle.fill" : "text.bubble.fill")
                                .foregroundStyle(note.kind == .tk ? Color.red : model.prefs.theme.accentColor)
                            Text(note.text.isEmpty ? "Empty note" : note.text)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 3)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Text("Tip: leave yourself a margin note with ⌘⇧M, or type TK as a placeholder for facts to fill in later.")
                    .font(.caption).foregroundStyle(.secondary).padding(.top, 10)
            }
        }
    }
}

private struct StylePane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let counts = Dictionary(grouping: model.lensMatches, by: \.kind).mapValues(\.count)
        VStack(alignment: .leading, spacing: 14) {
            PaneTitle(title: "Style Lens")
            Toggle("Highlight in text", isOn: Bindable(model.prefs).styleLens)
                .toggleStyle(.switch)
            ForEach(StyleLens.Kind.allCases) { kind in
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(nsColor: kind.color))
                        .frame(width: 12, height: 12)
                        .padding(.top, 3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(kind.label).font(.body.weight(.medium))
                        Text(kind.hint).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(counts[kind] ?? 0)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                }
            }
            Divider()
            PaneTitle(title: "Readability")
            HStack(alignment: .firstTextBaseline) {
                Text(model.stats.readingEase.map { "\(Int($0))" } ?? "—")
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                Text(model.stats.readingEaseLabel).foregroundStyle(.secondary)
            }
            Text("Flesch reading ease: 60–70 is plain English. Shorter sentences and simpler words score higher.")
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            RhythmSection()
        }
    }
}

private struct StatsPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let s = model.stats
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(title: "Statistics")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                row("Words", s.words.formatted())
                row("Characters", s.characters.formatted())
                row("Without spaces", s.charactersNoSpaces.formatted())
                row("Sentences", s.sentences.formatted())
                row("Paragraphs", s.paragraphs.formatted())
                row("Avg. sentence", String(format: "%.1f words", s.averageSentenceLength))
                row("Reading time", s.readingTime.readableMinutes)
                row("Speaking time", s.speakingTime.readableMinutes)
                row("Pages (approx.)", String(format: "%.1f", Double(s.words) / 275))
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).font(.body.weight(.medium)).monospacedDigit().gridColumnAlignment(.trailing)
        }
    }
}

private struct HistoryPane: View {
    @Environment(AppModel.self) private var model
    @State private var previewing: Snapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                model.openTimeMachine()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "clock.arrow.circlepath").font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open Time Machine").font(.headline)
                        Text("Replay every moment of this sheet").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(model.prefs.theme.accentColor.opacity(0.25)).interactive(), in: .rect(cornerRadius: 14))
            .padding(.bottom, 6)

            PaneTitle(title: "Snapshots")
            Text("Save a version before a big rewrite. Wren also snapshots automatically when you make large changes.")
                .font(.callout).foregroundStyle(.secondary)
            Button {
                model.takeSnapshot()
            } label: {
                Label("Take Snapshot", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)

            ForEach(model.snapshots) { snapshot in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(snapshot.date, format: .dateTime.month().day().hour().minute())
                            .font(.body.weight(.medium))
                        Text("\(snapshot.words.formatted()) words · \(snapshot.date, format: .relative(presentation: .named))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { previewing = snapshot } label: { Image(systemName: "eye") }
                        .buttonStyle(.borderless)
                        .help("Preview")
                        .popover(item: Binding(get: { previewing == snapshot ? snapshot : nil }, set: { previewing = $0 })) { item in
                            ScrollView {
                                Text(SnapshotStore.text(of: item))
                                    .font(.system(.body, design: .serif))
                                    .textSelection(.enabled)
                                    .padding()
                            }
                            .frame(width: 420, height: 380)
                        }
                    Button { model.restore(snapshot) } label: { Image(systemName: "arrow.uturn.backward") }
                        .buttonStyle(.borderless)
                        .help("Restore this version (your current text is snapshotted first)")
                }
                .padding(10)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 10))
                .contextMenu {
                    Button("Delete Snapshot", role: .destructive) { model.deleteSnapshot(snapshot) }
                }
            }
        }
    }
}

private struct RhythmSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let lengths = Array(model.sentenceLengths.suffix(60))
        let tallest = max(30, lengths.max() ?? 1)
        let variety = Rhythm.variety(model.sentenceLengths)
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(title: "Rhythm")
            Toggle("Show rhythm gutter", isOn: Bindable(model.prefs).rhythm)
                .toggleStyle(.switch)
            if lengths.isEmpty {
                Text("Write a few sentences to see their rhythm.").font(.callout).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(Array(lengths.enumerated()), id: \.offset) { index, words in
                        UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                            .fill(Color(nsColor: Rhythm.Bucket(words: words).color))
                            .frame(maxWidth: 8)
                            .frame(height: max(3, 64 * CGFloat(words) / CGFloat(tallest)))
                            .help("Sentence \(model.sentenceLengths.count - lengths.count + index + 1): \(words) words")
                    }
                }
                .frame(height: 64, alignment: .bottom)
                .frame(maxWidth: .infinity, alignment: .leading)
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 4) {
                    GridRow {
                        legend(.short)
                        legend(.medium)
                    }
                    GridRow {
                        legend(.long)
                        legend(.veryLong)
                    }
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(variety.map(String.init) ?? "—")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text("variety").foregroundStyle(.secondary)
                }
                Text(advice(variety)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func legend(_ bucket: Rhythm.Bucket) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(Color(nsColor: bucket.color)).frame(width: 10, height: 10)
            Text(bucket.label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func advice(_ variety: Int?) -> String {
        guard let variety else { return "Write a few more sentences for a score." }
        switch variety {
        case ..<35: return "Monotonous. Your sentences are all about the same length. Add a short one. Then let the next one run long, winding through a clause or two before it lands."
        case ..<60: return "Decent rhythm. A few more short, punchy sentences would add energy."
        default: return "Lively rhythm. Your sentence lengths vary like real speech."
        }
    }
}

private struct CuttingRoomPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            PaneTitle(title: "Cutting Room Floor")
            Text("Every passage you delete lands here automatically, so you can cut boldly. Drag one back into the page or insert it at the cursor.")
                .font(.callout).foregroundStyle(.secondary)
            if model.cuts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "scissors").font(.largeTitle).foregroundStyle(.tertiary)
                    Text("Nothing on the floor yet").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
            ForEach(model.cuts) { cut in
                VStack(alignment: .leading, spacing: 8) {
                    Text(cut.text)
                        .font(.system(.callout, design: .serif))
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack {
                        Text(cut.date, format: .relative(presentation: .named)).font(.caption).foregroundStyle(.tertiary)
                        Spacer()
                        Button { model.insertCut(cut) } label: { Image(systemName: "text.insert") }
                            .help("Insert at cursor")
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(cut.text, forType: .string)
                        } label: { Image(systemName: "doc.on.doc") }
                            .help("Copy")
                        Button { withAnimation { model.deleteCut(cut) } } label: { Image(systemName: "trash") }
                            .help("Throw away for good")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(12)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12))
                .draggable(cut.text)
            }
        }
    }
}
