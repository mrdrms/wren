import SwiftUI

/// The Pomodoro in the status bar: a ring and countdown, with controls in its menu.
struct PomodoroChip: View {
    @Environment(AppModel.self) private var model
    @State private var showingControls = false

    var body: some View {
        let pomodoro = model.pomodoro
        let tint = pomodoro.phase.isBreak ? model.prefs.theme.leafColor : model.prefs.theme.accentColor
        if pomodoro.isActive {
            // A plain button with a popover: stable to click, even while the countdown ticks.
            Button { showingControls.toggle() } label: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    HStack(spacing: 6) {
                        GoalRing(progress: pomodoro.progress(at: context.date), lineWidth: 2.5, tint: tint)
                            .frame(width: 15, height: 15)
                        Text(Duration.seconds(pomodoro.remaining(at: context.date).rounded(.up)), format: .time(pattern: .minuteSecond))
                            .monospacedDigit()
                        if !pomodoro.isRunning {
                            Image(systemName: "pause.fill").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(tint)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("\(pomodoro.phase.label). Click to pause, skip or stop.")
            .accessibilityLabel("Pomodoro controls")
            .popover(isPresented: $showingControls, arrowEdge: .top) {
                PomodoroControls { showingControls = false }
                    .environment(model)
            }
            .contextMenu { PomodoroMenuItems() }
        } else if model.prefs.pomodoroEnabled {
            Button {
                model.startPomodoro()
            } label: {
                Label("Focus \(model.prefs.pomodoroWork)m", systemImage: "timer")
            }
            .buttonStyle(.plain)
            .foregroundStyle(model.prefs.theme.accentColor)
            .help("Start a \(model.prefs.pomodoroWork)-minute focus session (⌥⌘P)")
        }
    }
}

/// Pause, skip and stop, shared by the context menu and the menu bar.
struct PomodoroMenuItems: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let pomodoro = model.pomodoro
        if pomodoro.isRunning {
            Button("Pause") { pomodoro.pause() }
        } else if pomodoro.isActive {
            Button("Resume") { model.startPomodoro() }
        }
        Button(pomodoro.phase.isBreak ? "Skip Break" : "Skip to Break") { pomodoro.skip() }
        Divider()
        Button("Stop Pomodoro", role: .destructive) { model.stopPomodoro() }
    }
}

/// The Pomodoro's control panel: time left, and clear ways to pause, skip or stop.
struct PomodoroControls: View {
    @Environment(AppModel.self) private var model
    let close: () -> Void

    var body: some View {
        let pomodoro = model.pomodoro
        let tint = pomodoro.phase.isBreak ? model.prefs.theme.leafColor : model.prefs.theme.accentColor
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(pomodoro.phase.label, systemImage: pomodoro.phase.isBreak ? "cup.and.saucer.fill" : "timer")
                    .font(.headline)
                    .foregroundStyle(tint)
                Spacer()
                Text("\(pomodoro.completedToday) 🍅 today").font(.caption).foregroundStyle(.secondary)
            }
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 8) {
                    Text(Duration.seconds(pomodoro.remaining(at: context.date).rounded(.up)), format: .time(pattern: .minuteSecond))
                        .font(.system(size: 40, weight: .light, design: .rounded))
                        .monospacedDigit()
                    ProgressView(value: pomodoro.progress(at: context.date)).tint(tint)
                }
            }
            HStack(spacing: 8) {
                if pomodoro.isRunning {
                    Button { pomodoro.pause() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }
                } else {
                    Button { model.startPomodoro() } label: { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }
                }
                Button { pomodoro.skip() } label: {
                    Label(pomodoro.phase.isBreak ? "Skip Break" : "Skip", systemImage: "forward.end.fill").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            Button(role: .destructive) {
                model.stopPomodoro()
                close()
            } label: {
                Label("Stop Pomodoro", systemImage: "stop.fill").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.red)
            .controlSize(.large)
            SettingsLink {
                Text("Change session lengths…").font(.caption)
            }
            .buttonStyle(.link)
        }
        .padding(18)
        .frame(width: 280)
    }
}

/// A calm full-window pause between sessions, with a breathing guide.
struct BreakScreen: View {
    @Environment(AppModel.self) private var model
    @State private var start = Date.now

    var body: some View {
        let pomodoro = model.pomodoro
        ZStack {
            Rectangle().fill(.ultraThinMaterial).ignoresSafeArea()
            VStack(spacing: 26) {
                Text(pomodoro.phase == .longBreak ? "Long break" : "Take a breath")
                    .font(.system(.largeTitle, design: .serif).weight(.semibold))
                // One clock drives both the circle and its label: 4 s in, 4 s out.
                TimelineView(.animation) { context in
                    let t = context.date.timeIntervalSince(start)
                    let fullness = (sin(t * .pi / 4 - .pi / 2) + 1) / 2
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [.mint.opacity(0.55), .teal.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                            .frame(width: 200, height: 200)
                            .scaleEffect(0.55 + 0.45 * fullness)
                        Text(sin(t * .pi / 4) >= 0 ? "Breathe in" : "Breathe out")
                            .font(.title3.weight(.medium))
                    }
                }
                .frame(width: 220, height: 220)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Duration.seconds(pomodoro.remaining(at: context.date).rounded(.up)), format: .time(pattern: .minuteSecond))
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .monospacedDigit()
                }
                Text(tip)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                HStack(spacing: 12) {
                    Button("Skip Break") { pomodoro.skip() }
                        .buttonStyle(.glass)
                    Button("Hide") { withAnimation { model.showBreakScreen = false } }
                        .buttonStyle(.glass)
                        .keyboardShortcut(.cancelAction)
                    Button("End Pomodoro", role: .destructive) { model.stopPomodoro() }
                        .buttonStyle(.glass)
                        .tint(.red)
                }
                .controlSize(.large)
                Text("\(pomodoro.completedToday) 🍅 finished today")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(40)
        }
    }

    private var tip: String {
        let tips = [
            "Stand up and stretch your shoulders.",
            "Look at something 20 feet away for 20 seconds.",
            "Refill your water. Your brain will thank you.",
            "Don't check your phone. Let your mind wander instead.",
            "Walk around the room. The next sentence often shows up on its own.",
        ]
        return tips[(model.pomodoro.completedToday + model.pomodoro.cycle) % tips.count]
    }
}

/// A brief reminder of how to step back out, shown as Zen or preview-alone begins.
struct ImmersiveHint: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "leaf.fill")
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .themedGlass(in: .capsule)
    }
}

/// Write | Split | Preview, always visible in the toolbar.
/// Clicking Side by Side or Preview again goes back to writing, like a toggle.
/// One Preview button: click for the reader's view of the post, ⌥-click (or its menu) to see
/// it beside the page. In a book, the useful preview is the printed spread, so it opens that.
struct PreviewButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let accent = model.prefs.theme.accentColor
        if let book = model.currentBook {
            Button { model.compileFolder = book } label: {
                Label("Book Preview", systemImage: "book.pages")
            }
            .help("See the book as printed pages, two at a time")
        } else {
            let previewing = model.previewMode != .off
            Menu {
                Button("Reader Preview") { model.setPreview(.full) }
                Button("Side by Side") { model.setPreview(.split) }
                if previewing {
                    Divider()
                    Button("Back to Writing") { model.setPreview(.off) }
                }
            } label: {
                Label("Preview", systemImage: previewing ? "eye.fill" : "eye")
            } primaryAction: {
                if previewing {
                    model.setPreview(.off)
                } else {
                    model.setPreview(NSEvent.modifierFlags.contains(.option) ? .split : .full)
                }
            }
            .tint(previewing ? accent : nil)
            .help(previewing ? "Back to writing (⌘⇧P)" : "How readers will see this post. ⌥-click to see it beside the page.")
        }
    }
}

/// Floating glass tinted with the current atmosphere, so controls belong to the scene.
struct ThemedGlass<S: Shape>: ViewModifier {
    @Environment(AppModel.self) private var model
    let shape: S
    var interactive = false

    func body(content: Content) -> some View {
        let theme = model.prefs.theme
        let glass = Glass.regular.tint(theme.panelColor.opacity(theme.isDark ? 0.6 : 0.65))
        content
            .foregroundStyle(theme.fg)
            .glassEffect(interactive ? glass.interactive() : glass, in: shape)
            .overlay(shape.stroke(theme.accentColor.opacity(0.12), lineWidth: 1))
    }
}

extension View {
    func themedGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(ThemedGlass(shape: shape, interactive: interactive))
    }
}
