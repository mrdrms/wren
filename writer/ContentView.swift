import AppKit
import Combine
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var escapeMonitor: Any?
    @State private var pointerMonitor: Any?
    @State private var sceneFrame: CGRect = .zero
    @State private var ritual = Preferences.shared.launchRitual
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        // Zen, a full preview and the welcome page all have the window to themselves.
        .onChange(of: model.isImmersive || model.showWelcome, initial: true) { _, immersive in
            withAnimation(.smooth(duration: 0.3)) {
                if immersive {
                    // Only the first fold remembers: a rebuilt window would otherwise record
                    // the already-folded sidebar as the one to bring back.
                    if model.columnsBeforeImmersive == nil { model.columnsBeforeImmersive = model.columnVisibility }
                    model.columnVisibility = .detailOnly
                } else if let previous = model.columnsBeforeImmersive {
                    if model.columnVisibility == .detailOnly { model.columnVisibility = previous }
                    model.columnsBeforeImmersive = nil
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
        // The inspector describes a sheet, so it stays closed on the welcome page.
        .inspector(isPresented: Binding(get: { model.showInspector && !model.showWelcome },
                                        set: { model.showInspector = $0 })) {
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
        .overlay {
            if ritual && !reduceMotion {
                LaunchRitual {
                    withAnimation(.easeInOut(duration: 0.7)) { ritual = false }
                }
                .transition(.opacity)
            }
        }
        .onChange(of: model.openedFromFinder) { _, opened in
            if opened { ritual = false }
        }
        .sheet(item: $model.drawingSession) { session in
            DrawingStudio(drawing: session.drawing, isNew: session.image == nil,
                          doneTitle: session.sheet == nil ? "Create Sheet" : nil,
                          onCancel: { model.drawingSession = nil },
                          onDone: { model.finishDrawing(session, $0) })
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $model.showJourney) { JourneyView() }
        .sheet(isPresented: $model.showTimeMachine) { TimeMachineView() }
        .sheet(item: $model.linkDraft) { draft in LinkSheet(draft: draft) }
        .sheet(isPresented: $model.showTemplates) { TemplateGallery() }
        .sheet(isPresented: $model.showPublish) { PublishSheet() }
        .sheet(item: $model.aiPending) { pending in AIConfirmSheet(pending: pending) }
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
            model.reloadIfChangedOnDisk()
        }
        .onAppear {
            // Minimal mode: a deliberate move of the pointer (not a brush of the trackpad while
            // typing) or a click brings the faded controls back.
            NSApp.windows.forEach { $0.acceptsMouseMovedEvents = true }
            var travelled: CGFloat = 0
            pointerMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .scrollWheel]) { [model] event in
                guard model.chromeHidden else { travelled = 0; return event }
                if event.type == .mouseMoved {
                    travelled += abs(event.deltaX) + abs(event.deltaY)
                    guard travelled > 24 else { return event }
                } else if event.type == .scrollWheel {
                    return event
                }
                travelled = 0
                model.chromeHidden = false
                return event
            }
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
