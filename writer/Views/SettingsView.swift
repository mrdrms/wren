import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        TabView {
            Tab("Appearance", systemImage: "paintpalette") { AppearanceSettings() }
            Tab("Writing", systemImage: "pencil.and.outline") { WritingSettings() }
            Tab("Focus", systemImage: "timer") { FocusSettings() }
            Tab("Publishing", systemImage: "paperplane") { PublishingSettings() }
            Tab("AI", systemImage: "sparkle") { AISettings() }
        }
        .frame(width: 560)
        .preferredColorScheme(model.prefs.theme.colorScheme)
    }
}

private struct AppearanceSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Section("Theme") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 14) {
                    ForEach(Theme.all) { theme in
                        AtmosphereCard(theme: theme, selected: prefs.themeID == theme.id)
                            .onTapGesture { withAnimation { prefs.themeID = theme.id } }
                    }
                }
                .padding(.vertical, 6)
                Toggle("Animate the scene (Starlight, Terminal)", isOn: $prefs.ambient)
                Text("Off by default, so nothing moves while you write.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Typography") {
                Picker("Font", selection: $prefs.font) {
                    ForEach(EditorFontChoice.allCases) { Text($0.label).tag($0) }
                }
                if let forced = prefs.theme.font {
                    Text("\(prefs.theme.name) uses \(forced.label) while it's active.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Size") {
                    Slider(value: $prefs.fontSize, in: 13...30, step: 1) { EmptyView() }
                    Text("\(Int(prefs.fontSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Line height") {
                    Slider(value: $prefs.lineHeight, in: 1.2...2.2, step: 0.05) { EmptyView() }
                    Text(String(format: "%.2f", prefs.lineHeight)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                LabeledContent("Line width") {
                    Slider(value: $prefs.lineWidth, in: 480...1000, step: 20) { EmptyView() }
                    Text("\(Int(prefs.lineWidth))").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ThemeSwatch: View {
    let theme: Theme
    let selected: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10).fill(theme.bg)
                VStack(alignment: .leading, spacing: 4) {
                    Capsule().fill(Color(nsColor: theme.heading)).frame(width: 40, height: 6)
                    Capsule().fill(theme.fg.opacity(0.6)).frame(width: 64, height: 4)
                    Capsule().fill(theme.fg.opacity(0.6)).frame(width: 52, height: 4)
                    Capsule().fill(theme.accentColor).frame(width: 28, height: 4)
                }
                .padding(10)
            }
            .frame(height: 64)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(selected ? theme.accentColor : Color.secondary.opacity(0.25), lineWidth: selected ? 2.5 : 1)
            }
            Text(theme.name).font(.caption.weight(selected ? .semibold : .regular))
        }
        .contentShape(.rect)
    }
}

private struct WritingSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Section {
                Picker("The editor shows", selection: $prefs.liveFormatting) {
                    Text("Plain Markdown").tag(false)
                    Text("Live formatting").tag(true)
                }
                .pickerStyle(.radioGroup)
                Toggle("Hide formatting marks (show them only on the line you're editing)", isOn: $prefs.hideMarkup)
                    .disabled(!prefs.liveFormatting)
                Toggle("Show the format bar", isOn: $prefs.showFormatBar)
                Toggle("Hide controls while typing", isOn: $prefs.minimalWhileTyping)
                Toggle("Wet ink: new words dry onto the page", isOn: $prefs.wetInk)
                Toggle("Opening ritual: the ensō and seal when Wren starts", isOn: $prefs.launchRitual)
                Text("The format bar and status pill fade as you type. Move the pointer to bring them back.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Formatting")
            } footer: {
                Text("Type / on an empty line to insert headings, lists, images and more. Select text for quick formatting.")
                    .foregroundStyle(.secondary)
            }
            Section("Flow") {
                Picker("Focus mode", selection: $prefs.focus) {
                    ForEach(FocusLevel.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Typewriter scrolling", isOn: $prefs.typewriter)
                Toggle("Flow Lock (strike instead of delete)", isOn: $prefs.flowLock)
                Toggle("Style Lens", isOn: $prefs.styleLens)
                Toggle("Rhythm gutter", isOn: $prefs.rhythm)
                Toggle("Key sounds", isOn: $prefs.keySounds)
            }
            Section("Goals") {
                Stepper("Daily goal: \(prefs.dailyGoal.formatted()) words", value: $prefs.dailyGoal, in: 50...20_000, step: 50)
            }
            Section {
                Toggle("Name new sheets after their first line", isOn: $prefs.autoTitle)
                LabeledContent("Library") {
                    Button("Show in Finder") { model.revealInFinder(model.library.defaultRoot) }
                }
            } header: {
                Text("Files")
            } footer: {
                Text("Your writing is saved as plain Markdown files. Open them in any app and sync them with iCloud Drive, Dropbox or Git.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct FocusSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var prefs = model.prefs
        Form {
            Section("Zen mode") {
                Toggle("Go full screen in Zen mode", isOn: $prefs.zenFullScreen)
                Text("Zen (⌘⇧↩) hides everything but the page, or the preview. Press Esc to come back.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("Show Pomodoro timer in the status bar", isOn: $prefs.pomodoroEnabled)
                Stepper("Focus session: \(prefs.pomodoroWork) min", value: $prefs.pomodoroWork, in: 5...90, step: 5)
                Stepper("Short break: \(prefs.pomodoroShortBreak) min", value: $prefs.pomodoroShortBreak, in: 1...30)
                Stepper("Long break: \(prefs.pomodoroLongBreak) min", value: $prefs.pomodoroLongBreak, in: 5...60, step: 5)
                Stepper("Long break after every \(prefs.pomodoroLongEvery) sessions", value: $prefs.pomodoroLongEvery, in: 2...8)
                Toggle("Enter Zen mode when a focus session starts", isOn: $prefs.pomodoroZen)
                Toggle("Show the break screen during breaks", isOn: $prefs.pomodoroBreakScreen)
                Toggle("Start the next focus session automatically", isOn: $prefs.pomodoroAutoStart)
            } header: {
                Text("Pomodoro")
            } footer: {
                Text("Work in focused sessions with short breaks in between. Changes apply from the next session.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
