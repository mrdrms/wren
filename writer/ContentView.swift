import AppKit
import Combine
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var escapeMonitor: Any?
    @State private var sceneFrame: CGRect = .zero
    /// The sidebar as it was before Zen or a full preview folded it away.
    @State private var columnsBeforeImmersive: NavigationSplitViewVisibility?

    var body: some View {
        @Bindable var model = model
        let theme = model.prefs.theme
        ZStack {
            // Navigator and page; the inspector joins only when asked for. Zen and preview-alone
            // fold the sidebar away rather than layering a second editor screen on top, so
            // there is only ever one page and nothing is left behind when they end.
            NavigationSplitView(columnVisibility: $model.columnVisibility) {
                NavigatorView()
            } detail: {
                EditorScreen()
            }
        }
        .onChange(of: model.isImmersive) { _, immersive in
            withAnimation(.smooth(duration: 0.3)) {
                if immersive {
                    columnsBeforeImmersive = model.columnVisibility
                    model.columnVisibility = .detailOnly
                } else if let previous = columnsBeforeImmersive {
                    if model.columnVisibility == .detailOnly { model.columnVisibility = previous }
                    columnsBeforeImmersive = nil
                }
            }
        }
        .background {
            // Measure the whole window once; panels draw their slice of one scene.
            Color.clear
                .ignoresSafeArea()
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { sceneFrame = $0 }
        }
        .environment(\.sceneFrame, sceneFrame)
        .inspector(isPresented: $model.showInspector) {
            InspectorView()
        }
        .toolbar(model.isImmersive ? .hidden : .automatic, for: .windowToolbar)
        .overlay {
            if model.showPalette {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { model.showPalette = false } }
                    CommandPalette()
                        .padding(.top, 90)
                        .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
                }
            }
        }
        .overlay {
            if let celebration = model.celebration {
                ZStack {
                    // Celebrations in the atmosphere's own colors.
                    ConfettiView(colors: [theme.accentColor, theme.leafColor] + theme.particles.map { Color(nsColor: $0) } + [Color(red: 1, green: 0.84, blue: 0.4)])
                    CelebrationCard(celebration: celebration)
                        .transition(.scale(scale: 0.7).combined(with: .opacity))
                        .onTapGesture { withAnimation { model.celebration = nil } }
                }
                .id(celebration.id)
            }
        }
        .overlay {
            if model.showBreakScreen && model.pomodoro.phase.isBreak {
                BreakScreen()
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .top) {
            if let hint = model.hint {
                ImmersiveHint(text: hint)
                    .padding(.top, 24)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $model.showJourney) { JourneyView() }
        .sheet(isPresented: $model.showTimeMachine) { TimeMachineView() }
        .sheet(item: $model.linkDraft) { draft in LinkSheet(draft: draft) }
        .sheet(isPresented: $model.showTemplates) { TemplateGallery() }
        .sheet(isPresented: Binding(get: { model.compileFolder != nil }, set: { if !$0 { model.compileFolder = nil } })) {
            if let folder = model.compileFolder { CompileSheet(folder: folder) }
        }
        .alert("Rename", isPresented: Binding(get: { model.renameTarget != nil }, set: { if !$0 { model.renameTarget = nil } })) {
            TextField("Name", text: $model.renameText)
            Button("Rename") { model.commitRename() }
            Button("Cancel", role: .cancel) { model.renameTarget = nil }
        }
        .alert("New Folder", isPresented: Binding(get: { model.newFolderParent != nil }, set: { if !$0 { model.newFolderParent = nil } })) {
            TextField("Folder name", text: $model.newFolderName)
            Button("Create") { model.commitNewFolder() }
            Button("Cancel", role: .cancel) { model.newFolderParent = nil }
        }
        .tint(theme.accentColor)
        .preferredColorScheme(theme.colorScheme)
        .animation(.snappy(duration: 0.2), value: model.showPalette)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            model.saveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            model.saveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.library.refresh()
        }
        .onAppear {
            // Esc steps out of Zen, a full preview, the board or the break screen,
            // unless a sheet or the palette is in charge of the keyboard.
            escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [model] event in
                guard event.keyCode == 53, !model.showPalette, !model.editorPopupOpen, event.window?.attachedSheet == nil,
                      event.window?.sheetParent == nil, model.handleEscape() else { return event }
                return nil
            }
        }
    }
}
