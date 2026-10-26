import AppKit
import Combine
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var escapeMonitor: Any?
    @State private var sceneFrame: CGRect = .zero

    var body: some View {
        @Bindable var model = model
        let theme = model.prefs.theme
        ZStack {
            // The sheet list can be hidden: then it's sidebar + editor. The editor itself is
            // kept alive across the switch, so nothing is lost.
            if model.prefs.showSheetList {
                NavigationSplitView(columnVisibility: $model.columnVisibility) {
                    SidebarView()
                } content: {
                    SheetListView()
                } detail: {
                    detail(theme)
                }
            } else {
                NavigationSplitView(columnVisibility: $model.columnVisibility) {
                    SidebarView()
                } detail: {
                    detail(theme)
                }
            }
            // Zen and preview-alone: the page takes over the window. The split view stays
            // as it was underneath, so leaving brings everything back exactly.
            if model.isImmersive {
                EditorScreen()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.3), value: model.isImmersive)
        .animation(.smooth(duration: 0.3), value: model.prefs.showSheetList)
        .background {
            // Measure the whole window once; panels draw their slice of one scene.
            GeometryReader { proxy in
                Color.clear
                    .onAppear { sceneFrame = proxy.frame(in: .global) }
                    .onChange(of: proxy.frame(in: .global)) { sceneFrame = proxy.frame(in: .global) }
            }
            .ignoresSafeArea()
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

    @ViewBuilder
    private func detail(_ theme: Theme) -> some View {
        if model.isImmersive {
            AtmosphereView(theme: theme, animated: false).ignoresSafeArea()
        } else {
            EditorScreen()
        }
    }
}
