import SwiftUI

@main
struct WrenApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        Window("Wren", id: "main") {
            ContentView()
                .environment(model)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1320, height: 840)
        .windowToolbarStyle(.unified)
        .commands { WrenCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct WrenCommands: Commands {
    let model: AppModel

    var body: some Commands {
        let prefs = model.prefs
        CommandGroup(replacing: .newItem) {
            Button("New Sheet") { model.newSheet() }
                .keyboardShortcut("n")
            Button("New from Template…") { model.showTemplates = true }
                .keyboardShortcut("n", modifiers: [.command, .option])
            Button("New Folder…") { model.beginNewFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Add Folder to Library…") { model.addFolder() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Take Snapshot") { model.takeSnapshot() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(model.loadedURL == nil)
        }
        CommandGroup(replacing: .importExport) {
            Button("Export as HTML…") { model.export("html") }
                .keyboardShortcut("e")
            Button("Export as PDF…") { model.export("pdf") }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            Button("Export as Word…") { model.export("docx") }
            Button("Export as Markdown…") { model.export("md") }
            Button("Export for Blog…") { model.export("blog") }
                .keyboardShortcut("e", modifiers: [.command, .option])
            Button("Copy as HTML") { model.export("copy") }
            Divider()
            Button("Check for Secrets…") { model.checkForSecrets() }
                .keyboardShortcut("c", modifiers: [.command, .option])
        }
        CommandMenu("Format") {
            Button("Bold") { model.format(.bold) }.keyboardShortcut("b")
            Button("Italic") { model.format(.italic) }.keyboardShortcut("i")
            Button("Highlight") { model.format(.highlight) }.keyboardShortcut("h", modifiers: [.command, .shift])
            Button("Strikethrough") { model.format(.strikethrough) }.keyboardShortcut("x", modifiers: [.command, .shift])
            Button("Inline Code") { model.format(.code) }.keyboardShortcut("`")
            Button("Link") { model.format(.link) }.keyboardShortcut("l")
            Divider()
            Button("Heading 1") { model.format(.heading(1)) }.keyboardShortcut("1")
            Button("Heading 2") { model.format(.heading(2)) }.keyboardShortcut("2")
            Button("Heading 3") { model.format(.heading(3)) }.keyboardShortcut("3")
            Button("Quote") { model.format(.quote) }.keyboardShortcut("'")
            Button("Body Text") { model.format(.paragraph) }.keyboardShortcut("0")
            Button("Bulleted List") { model.format(.bullet) }.keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Numbered List") { model.format(.numbered) }.keyboardShortcut("7", modifiers: [.command, .shift])
            Button("Checklist") { model.format(.task) }.keyboardShortcut("9", modifiers: [.command, .shift])
            Button("Divider") { model.format(.divider) }
            Button("Code Block") { model.format(.codeBlock) }
            Divider()
            Button("Margin Note") { model.format(.note) }.keyboardShortcut("m", modifiers: [.command, .shift])
            Button("Insert Image or Video…") { model.insertMediaWithPanel() }.keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Embed YouTube Video…") { model.beginVideoEmbed() }
            Button("Add Post Details") { model.insertPostDetails() }
            Divider()
            Toggle("Live Formatting", isOn: Bindable(prefs).liveFormatting)
                .keyboardShortcut("m", modifiers: [.command, .option])
            Toggle("Hide Formatting Marks", isOn: Bindable(prefs).hideMarkup)
                .disabled(!prefs.liveFormatting)
            Toggle("Show Format Bar", isOn: Bindable(prefs).showFormatBar)
        }
        CommandMenu("Write") {
            Button("Command Palette…") { model.showPalette.toggle() }
                .keyboardShortcut("k")
            Divider()
            Button("Focus Mode: \(prefs.focus.label)") { prefs.cycleFocus() }
                .keyboardShortcut("f", modifiers: [.command, .shift])
            Toggle("Typewriter Mode", isOn: Bindable(prefs).typewriter)
                .keyboardShortcut("t", modifiers: [.command, .shift])
            Button(prefs.flowLock ? "Turn Off Flow Lock" : "Turn On Flow Lock") { model.toggleFlowLock() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Button("Sweep Struck Text") { model.sweepGhosts() }
                .keyboardShortcut(.delete, modifiers: [.command, .option])
                .disabled(model.ghostCount == 0)
            Button("Restore Struck Text") { model.restoreGhosts() }
                .disabled(model.ghostCount == 0)
            Divider()
            Toggle("Style Lens", isOn: Bindable(prefs).styleLens)
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Toggle("Rhythm Gutter", isOn: Bindable(prefs).rhythm)
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button(model.isReading ? "Stop Reading" : "Read Aloud") { model.toggleReadAloud() }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Button(model.boardMode ? "Back to Writing" : "Storyboard") { model.toggleBoard() }
                .keyboardShortcut("b", modifiers: [.command, .shift])
            Button("Preview: \(model.previewMode == .off ? "Side by Side" : model.previewMode == .split ? "Full" : "Off")") { model.cyclePreview() }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Menu("Blog Style") {
                Picker("Blog Style", selection: Bindable(prefs).blogStyle) {
                    ForEach(BlogStyle.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Button("Time Machine…") { model.openTimeMachine() }
                .keyboardShortcut("y", modifiers: [.command, .shift])
            Button("Cutting Room Floor") { model.inspectorTab = .cuts; model.showInspector = true }
            Toggle("Key Sounds", isOn: Bindable(prefs).keySounds)
            Toggle("Zen Mode", isOn: Bindable(model).zen)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            Divider()
            Menu("Writing Sprint") {
                ForEach([5, 15, 25, 45], id: \.self) { minutes in
                    Button("\(minutes) Minutes") { model.startSprint(minutes: minutes) }
                }
                if model.sprint != nil {
                    Divider()
                    Button("Finish Sprint") { model.finishSprint() }
                }
            }
            Menu("Pomodoro") {
                Button(model.pomodoro.isRunning ? "Pause" : (model.pomodoro.isActive ? "Resume" : "Start Focus Session")) {
                    if model.pomodoro.isRunning { model.pomodoro.pause() } else { model.startPomodoro() }
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                Button(model.pomodoro.phase.isBreak ? "Skip Break" : "Skip to Break") { model.pomodoro.skip() }
                    .disabled(!model.pomodoro.isActive)
                Button("Stop Pomodoro") { model.stopPomodoro() }
                    .disabled(!model.pomodoro.isActive)
            }
            Button("Writing Journey") { model.showJourney = true }
                .keyboardShortcut("j", modifiers: [.command, .shift])
            Divider()
            Menu("Theme") {
                Picker("Theme", selection: Bindable(prefs).themeID) {
                    ForEach(Theme.all) { Text($0.name).tag($0.id) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        }
        CommandGroup(after: .sidebar) {
            Button(model.navigatorPage == .library ? "Show Sheets" : "Show Library") { model.toggleLibrary() }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button("Toggle Inspector") { model.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .option])
            Divider()
            Button(model.companion == nil ? "Open Second Editor" : "Close Second Editor") { model.toggleCompanion() }
                .keyboardShortcut("3", modifiers: [.command, .option])
                .disabled(model.loadedURL == nil)
            Button("Swap Editors") { model.swapEditors() }
                .disabled(model.companion == nil)
        }
    }
}
