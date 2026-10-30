import SwiftUI

/// The drawing screen, the same on every device: tools along the top, the sheet of paper
/// below. Keyboard shortcuts work wherever there's a keyboard.
struct DrawingStudio: View {
    @State private var editor: InkEditor
    let isNew: Bool
    /// What the finishing button says; by default Insert for a new drawing, Save for an edit.
    let doneTitle: String?
    let onCancel: () -> Void
    let onDone: (WrenDrawing) -> Void
    @State private var confirmDiscard = false

    init(drawing: WrenDrawing, isNew: Bool, doneTitle: String? = nil,
         onCancel: @escaping () -> Void, onDone: @escaping (WrenDrawing) -> Void) {
        _editor = State(initialValue: InkEditor(drawing: drawing))
        self.isNew = isNew
        self.doneTitle = doneTitle
        self.onCancel = onCancel
        self.onDone = onDone
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    if editor.hasChanges { confirmDiscard = true } else { onCancel() }
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                Text(isNew ? "New Drawing" : "Edit Drawing")
                    .font(.headline)
                Spacer()
                Button(doneTitle ?? (isNew ? "Insert" : "Save")) { onDone(editor.drawing) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(editor.drawing.isEmpty || !editor.hasChanges)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            InkToolbar(editor: editor)
                .padding(.horizontal, 18)
                .padding(.bottom, 12)

            InkCanvas(editor: editor)
                .aspectRatio(editor.drawing.width / editor.drawing.height, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.black.opacity(0.08)))
                .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
                .padding(.horizontal, 22)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #if os(macOS)
        .frame(minWidth: 780, idealWidth: 940, minHeight: 620, idealHeight: 720)
        #endif
        .confirmationDialog("Discard this drawing's changes?", isPresented: $confirmDiscard) {
            Button("Discard Changes", role: .destructive, action: onCancel)
            Button("Keep Drawing", role: .cancel) {}
        }
    }
}

/// Tools, colors and sizes in one row, then undo, redo and clear.
struct InkToolbar: View {
    let editor: InkEditor

    var body: some View {
        @Bindable var editor = editor
        HStack(spacing: 14) {
            HStack(spacing: 2) {
                ForEach(InkTool.allCases) { tool in
                    let active = editor.tool == tool
                    Button { editor.tool = tool } label: {
                        Image(systemName: tool.symbol)
                            .font(.system(size: 15, weight: active ? .semibold : .regular))
                            .frame(width: 34, height: 30)
                            .foregroundStyle(active ? Color.accentColor : Color.primary)
                            .background(active ? Color.accentColor.opacity(0.16) : .clear, in: .rect(cornerRadius: 8))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(KeyEquivalent(Character(String(tool.label.prefix(1)).lowercased())), modifiers: [])
                    .help("\(tool.label) (\(tool.label.prefix(1)))")
                    .accessibilityLabel(tool.label)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.05), in: .rect(cornerRadius: 10))

            HStack(spacing: 8) {
                ForEach(InkColor.palette, id: \.self) { color in
                    let active = editor.color == color && editor.tool != .eraser
                    Button {
                        editor.color = color
                        if editor.tool == .eraser { editor.tool = .pen }
                    } label: {
                        Circle()
                            .fill(Color(cgColor: color.cgColor()))
                            .frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: active ? 2 : 0))
                            .padding(2)
                            .overlay(Circle().strokeBorder(active ? Color(cgColor: color.cgColor()) : .clear, lineWidth: 2))
                            .contentShape(.circle)
                    }
                    .buttonStyle(.plain)
                    .help(color.name)
                    .accessibilityLabel(color.name)
                    .accessibilityAddTraits(active ? .isSelected : [])
                }
            }

            HStack(spacing: 2) {
                ForEach(Array(InkEditor.sizes.enumerated()), id: \.offset) { index, size in
                    let active = editor.size == size
                    Button { editor.size = size } label: {
                        Circle()
                            .fill(Color.primary.opacity(active ? 0.85 : 0.35))
                            .frame(width: 5 + CGFloat(index) * 4, height: 5 + CGFloat(index) * 4)
                            .frame(width: 28, height: 28)
                            .background(active ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 7))
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .help(["Fine", "Medium", "Bold"][index])
                    .accessibilityLabel(["Fine", "Medium", "Bold"][index])
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 4) {
                Button { editor.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!editor.canUndo)
                    .help("Undo (⌘Z)")
                Button { editor.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!editor.canRedo)
                    .help("Redo (⇧⌘Z)")
                Button { editor.clear() } label: { Image(systemName: "trash") }
                    .disabled(editor.drawing.isEmpty)
                    .help("Clear the page (undoable)")
            }
            .buttonStyle(.borderless)
            .font(.system(size: 14))
        }
    }
}
