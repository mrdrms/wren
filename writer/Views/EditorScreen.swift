import SwiftUI

struct EditorScreen: View {
    @Environment(AppModel.self) private var model
    @State private var hoveringHUD = false
    @AppStorage("companionFraction") private var companionFraction = 0.42

    var body: some View {
        let prefs = model.prefs
        let theme = prefs.theme
        ZStack(alignment: .bottom) {
            AtmosphereView(theme: theme, animated: prefs.ambient, continuous: true)
                .ignoresSafeArea()

            if model.loadedURL != nil {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        writingColumn
                            .opacity(model.previewMode == .full ? 0 : 1)
                            .allowsHitTesting(model.previewMode != .full)
                            .frame(maxWidth: model.previewMode == .full ? 0 : .infinity)
                        if model.previewMode != .off {
                            if model.previewMode == .split { Divider().ignoresSafeArea() }
                            PreviewPane()
                                .frame(maxWidth: .infinity)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        } else if let companion = model.companion, !model.zen, !model.boardMode {
                            // The preview and the second editor share this side; the preview wins.
                            CompanionDivider(fraction: $companionFraction, totalWidth: proxy.size.width)
                            CompanionPane(sheet: companion)
                                .frame(width: proxy.size.width * companionFraction)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            } else {
                EmptyEditor()
            }
        }
        .navigationTitle(model.zen ? "" : model.currentTitle)
        // The page runs up under the title bar, so the window reads as one sheet of paper.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Picker("Focus", selection: Bindable(prefs).focus) {
                        ForEach(FocusLevel.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Toggle("Typewriter Scrolling", isOn: Bindable(prefs).typewriter)
                } label: {
                    Label("Focus", systemImage: "scope")
                } primaryAction: {
                    prefs.cycleFocus()
                }
                .tint(prefs.focus == .off && !prefs.typewriter ? nil : theme.accentColor)
                .help("Focus mode: \(prefs.focus.label) (⌘⇧F). Typewriter scrolling is in this menu (⌘⇧T).")

                ToolsMenu()
            }
            ToolbarSpacer(.fixed)
            ToolbarItem(placement: .primaryAction) {
                PreviewButton()
            }
            ToolbarSpacer(.fixed)
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.toggleZen() } label: {
                    Label("Zen", systemImage: model.zen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }
                .help("Zen mode (⌘⇧↩)")
                Button {
                    withAnimation { model.showInspector.toggle() }
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help("Inspector (⌘⌥I)")
            }
        }
    }
}

/// The power tools, gathered in one place so the toolbar stays calm.
struct ToolsMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let prefs = model.prefs
        let active = prefs.flowLock || prefs.styleLens || prefs.rhythm || model.boardMode || model.isReading
        Menu {
            Section("Write") {
                Toggle("Flow Lock", isOn: Binding(get: { prefs.flowLock }, set: { _ in model.toggleFlowLock() }))
                Toggle("Storyboard", isOn: Binding(get: { model.boardMode }, set: { _ in model.toggleBoard() }))
                Menu("Writing Sprint") {
                    ForEach([5, 15, 25, 45], id: \.self) { minutes in
                        Button("\(minutes) Minutes") { model.startSprint(minutes: minutes) }
                    }
                }
                Button(model.pomodoro.isActive ? "Pomodoro Running…" : "Start Pomodoro") { model.startPomodoro() }
                    .disabled(model.pomodoro.isRunning)
            }
            Section("Edit") {
                Toggle("Style Lens", isOn: Bindable(prefs).styleLens)
                Toggle("Rhythm Gutter", isOn: Bindable(prefs).rhythm)
                Toggle("Read Aloud", isOn: Binding(get: { model.isReading }, set: { _ in model.toggleReadAloud() }))
            }
            Section("History") {
                Button("Time Machine…") { model.openTimeMachine() }
                Button("Take Snapshot") { model.takeSnapshot() }
                Button("Cutting Room Floor") { model.inspectorTab = .cuts; model.showInspector = true }
            }
        } label: {
            Label("Tools", systemImage: "wand.and.stars")
        }
        .menuIndicator(.hidden)
        .tint(active ? prefs.theme.accentColor : nil)
        .help("Flow Lock, Storyboard, Style Lens, Rhythm, Read Aloud, Time Machine and more")
    }
}

struct AtmosphereCard: View {
    let theme: Theme
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                AtmosphereView(theme: theme, scale: 0.6)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Aa")
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(nsColor: theme.heading))
                    Capsule().fill(theme.fg.opacity(0.35)).frame(width: 70, height: 3)
                    Capsule().fill(theme.fg.opacity(0.35)).frame(width: 52, height: 3)
                    Capsule().fill(theme.accentColor).frame(width: 26, height: 3)
                }
                .padding(10)
            }
            .frame(height: 96)
            .clipShape(.rect(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(selected ? theme.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 3 : 1)
            }
            Text(theme.name).font(.system(.callout, design: .serif).weight(.semibold))
            Text(theme.tagline).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .contentShape(.rect)
    }
}

extension EditorScreen {
    /// The editor plus whatever floats over it. The editor stays alive under the board and
    /// behind a full preview, so reordering stays one undoable edit and nothing reloads.
    @ViewBuilder
    var writingColumn: some View {
        ZStack(alignment: .bottom) {
            PageBand(theme: model.prefs.theme, lineWidth: model.prefs.lineWidth)
                .opacity(model.boardMode ? 0 : 1)

            // The format bar gets its own row, so text never scrolls underneath it.
            VStack(spacing: 0) {
                if model.prefs.showFormatBar && !model.boardMode && !model.zen {
                    FormatBar()
                        .padding(.top, 6)
                        .padding(.bottom, 6)
                        // Keeps its row while hidden, so the text never jumps.
                        .opacity(model.chromeHidden ? 0 : 1)
                        .allowsHitTesting(!model.chromeHidden)
                        .animation(.easeInOut(duration: model.chromeHidden ? 0.5 : 0.2), value: model.chromeHidden)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                MarkdownEditor(model: model)
                    .opacity(model.boardMode ? 0 : 1)
                    .allowsHitTesting(!model.boardMode)
            }

            if model.boardMode {
                StoryboardView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            } else {
                let faded = (model.chromeHidden || model.isTyping) && !hoveringHUD
                StatusHUD()
                    .opacity(faded ? (model.chromeHidden ? 0 : 0.12) : 1)
                    .animation(.easeInOut(duration: faded ? 0.6 : 0.25), value: faded)
                    .onHover { hoveringHUD = $0 }
                    .padding(.bottom, 18)
            }
        }
    }
}

/// The floating status bar: word count, goal ring, sprint clock and momentum flame.
struct StatusHUD: View {
    @Environment(AppModel.self) private var model
    @AppStorage("hudMetric") private var metric = 0

    var body: some View {
        let accent = model.prefs.theme.accentColor
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 14) {
                if let progress = model.documentProgress {
                    GoalRing(progress: progress, lineWidth: 2.5, tint: accent)
                        .frame(width: 16, height: 16)
                        .help("\(Int(progress * 100))% of your \(model.documentGoal ?? 0) word goal")
                }
                Button {
                    metric = (metric + 1) % 3
                } label: {
                    Text(metricText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: model.stats.words)
                }
                .buttonStyle(.plain)
                .help("Click to switch between words, characters and reading time")

                if let sprint = model.sprint {
                    Divider().frame(height: 14)
                    let remaining = max(0, sprint.end.timeIntervalSince(context.date))
                    HStack(spacing: 5) {
                        Image(systemName: "timer")
                        Text(Duration.seconds(remaining), format: .time(pattern: .minuteSecond))
                            .monospacedDigit()
                        Text("· \(model.sprintWords) words").foregroundStyle(.secondary)
                    }
                    .foregroundStyle(accent)
                    .contextMenu {
                        Button("Finish Sprint Now") { model.finishSprint() }
                        Button("Cancel Sprint", role: .destructive) { model.cancelSprint() }
                    }
                }

                if model.isReading {
                    Divider().frame(height: 14)
                    Button { model.stopReading() } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "speaker.wave.3.fill")
                                .symbolEffect(.variableColor.iterative, isActive: true)
                            Text("Reading")
                        }
                        .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                    .help("Stop reading (⌥⌘R)")
                }

                if model.ghostCount > 0 {
                    Divider().frame(height: 14)
                    Menu {
                        Button("Sweep Struck Text") { model.sweepGhosts() }
                        Button("Restore Struck Text") { model.restoreGhosts() }
                    } label: {
                        Label("\(model.ghostCount) struck", systemImage: "strikethrough")
                            .monospacedDigit()
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .fixedSize()
                    .help("Words you struck with Flow Lock. Sweep them away when you're ready (⌥⌘⌫).")
                }

                if model.prefs.flowLock {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(accent)
                        .help("Flow Lock is on")
                }

                if model.pomodoro.isActive || model.prefs.pomodoroEnabled {
                    Divider().frame(height: 14)
                    PomodoroChip()
                }

                Divider().frame(height: 14)
                MomentumFlame(level: model.momentum.level(at: context.date))
            }
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .themedGlass(in: .capsule, interactive: true)
    }

    private var metricText: String {
        let stats = model.stats
        switch metric {
        case 1: return "\(stats.characters.formatted()) characters"
        case 2: return "\(stats.readingTime.readableMinutes) read"
        default: return "\(stats.words.formatted()) words"
        }
    }
}

private struct EmptyEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Enso(color: Color(nsColor: model.prefs.theme.heading))
                .frame(width: 150, height: 150)
            Text("What will you write today?")
                .font(.system(size: 28, weight: .regular, design: .serif))
            Text("\(model.log.today.formatted()) of \(model.prefs.dailyGoal.formatted()) words so far today")
                .foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button("New Sheet") { model.newSheet() }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                Button("Choose a Template") { model.showTemplates = true }
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A soft column of page color under the text, so the scene stays alive in the margins
/// but never competes with the words.
struct PageBand: View {
    let theme: Theme
    let lineWidth: Double

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, lineWidth + 90)
            let strength = theme.isDark ? 0.6 : 0.7
            LinearGradient(stops: [
                .init(color: theme.bg.opacity(0), location: 0),
                .init(color: theme.bg.opacity(strength), location: 0.1),
                .init(color: theme.bg.opacity(strength), location: 0.9),
                .init(color: theme.bg.opacity(0), location: 1),
            ], startPoint: .leading, endPoint: .trailing)
            .frame(width: width)
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// An ensō: a single brushstroke circle, drawn as you arrive. In Zen it stands for a mind
/// free to let the work happen.
struct Enso: View {
    let color: Color
    @State private var progress: CGFloat = 0

    var body: some View {
        Canvas { g, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.42
            let steps = Int(220 * progress)
            guard steps > 1 else { return }
            for i in 0..<steps {
                let t = CGFloat(i) / 220
                // The brush starts heavy, thins out, and leaves a gap at the end.
                let angle = -.pi / 2.6 + t * .pi * 1.86
                let wobble = sin(t * 19) * 1.2
                let point = CGPoint(x: center.x + cos(angle) * (radius + wobble), y: center.y + sin(angle) * (radius + wobble))
                let width = max(1.2, 11 * pow(1 - t, 0.6) + 2 * sin(t * 7))
                let dry = t > 0.82 ? Double(1 - (t - 0.82) / 0.18) : 1
                g.fill(Path(ellipseIn: CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width)),
                       with: .color(color.opacity(0.85 * dry)))
            }
        }
        .onAppear {
            progress = 0
            withAnimation(.easeOut(duration: 1.8)) { progress = 1 }
        }
    }
}
