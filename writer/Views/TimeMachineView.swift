import AppKit
import SwiftUI

/// Plays a sheet's recorded history forwards and backwards, one typing pause at a time.
@Observable
final class TimeMachinePlayer {
    let changes: [TextChange]
    private(set) var index: Int
    private(set) var text: String
    var isPlaying = false
    var speed = 2
    @ObservationIgnored private let buffer = NSMutableString()

    init(changes all: [TextChange]) {
        // Keep only the changes that replay cleanly, so seeking either way stays consistent.
        var valid: [TextChange] = []
        for change in all where change.loc + (change.old as NSString).length <= buffer.length {
            change.apply(to: buffer)
            valid.append(change)
        }
        changes = valid
        index = valid.count
        text = buffer as String
    }

    var current: TextChange? { index > 0 ? changes[index - 1] : nil }
    var isAtEnd: Bool { index == changes.count }

    func seek(to target: Int) {
        let target = min(max(0, target), changes.count)
        while index < target { changes[index].apply(to: buffer); index += 1 }
        while index > target { index -= 1; changes[index].revert(on: buffer) }
        text = buffer as String
    }

    func play() async {
        if isAtEnd { seek(to: 0) }
        isPlaying = true
        while isPlaying && !isAtEnd {
            seek(to: index + speed)
            try? await Task.sleep(for: .milliseconds(45))
        }
        isPlaying = false
    }
}

struct TimeMachineView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var player: TimeMachinePlayer?

    var body: some View {
        let theme = model.prefs.theme
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title)
                    .foregroundStyle(theme.accentColor)
                    .symbolEffect(.rotate, isActive: player?.isPlaying == true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Time Machine").font(.title2.weight(.bold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            if let player, player.changes.count > 1 {
                ReplayTextView(text: player.text, highlight: player.current?.insertedRange, prefs: model.prefs)
                    .background(theme.bg)
                    .clipShape(.rect(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator))
                    .padding(.horizontal, 20)
                controls(player, accent: theme.accentColor)
            } else {
                ContentUnavailableView(
                    "History starts now",
                    systemImage: "clock.badge.checkmark",
                    description: Text("Wren records every pause in your typing. Keep writing, then come back to watch this sheet come to life."))
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 980, height: 720)
        .task { player = TimeMachinePlayer(changes: model.historyChanges()) }
        .onDisappear { player?.isPlaying = false }
    }

    private var subtitle: String {
        guard let player else { return "Loading…" }
        guard let change = player.current else { return "The very beginning" }
        let words = TextStats.contentWords(player.text)
        return "\(change.t.formatted(date: .abbreviated, time: .standard)) · \(words.formatted()) words · step \(player.index.formatted()) of \(player.changes.count.formatted())"
    }

    private func controls(_ player: TimeMachinePlayer, accent: Color) -> some View {
        @Bindable var player = player
        return HStack(spacing: 14) {
            Button {
                if player.isPlaying { player.isPlaying = false } else { Task { await player.play() } }
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 30, height: 30)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.space, modifiers: [])
            .help("Watch your draft write itself (Space)")

            Slider(value: Binding(get: { Double(player.index) }, set: { player.isPlaying = false; player.seek(to: Int($0)) }),
                   in: 0...Double(max(1, player.changes.count)), step: 1)

            Picker("Speed", selection: $player.speed) {
                Text("1×").tag(1)
                Text("2×").tag(2)
                Text("8×").tag(8)
                Text("32×").tag(32)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 150)

            Button {
                model.restoreFromHistory(player.text, date: player.current?.t ?? .now)
            } label: {
                Label("Restore This Moment", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(.glassProminent)
            .disabled(player.isAtEnd)
        }
        .padding(20)
    }
}

/// Read-only, fully styled rendering of a past version, with the latest change highlighted.
struct ReplayTextView: NSViewRepresentable {
    let text: String
    let highlight: NSRange?
    let prefs: Preferences

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 48, height: 32)
        textView.textContainer?.lineFragmentPadding = 0
        _ = textView.layoutManager // keep TextKit 1 for predictable attribute styling
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView, let storage = textView.textStorage else { return }
        let coordinator = context.coordinator
        guard text != coordinator.lastText || highlight != coordinator.lastHighlight else { return }
        coordinator.lastText = text
        coordinator.lastHighlight = highlight

        let highlighter = coordinator.highlighter
        highlighter.theme = prefs.theme
        highlighter.fontChoice = prefs.theme.font ?? prefs.font
        highlighter.fontSize = prefs.fontSize * 0.92
        highlighter.lineHeight = prefs.lineHeight
        storage.setAttributedString(NSAttributedString(string: text))
        highlighter.highlightAll(storage)
        if let highlight, NSMaxRange(highlight) <= storage.length {
            let range = highlight.length > 0 ? highlight : NSRange(location: highlight.location, length: 0)
            if range.length > 0 {
                storage.addAttribute(.backgroundColor, value: prefs.theme.accent.withAlphaComponent(prefs.theme.isDark ? 0.4 : 0.25), range: range)
            }
            textView.scrollRangeToVisible(range)
        }
    }

    final class Coordinator {
        let highlighter = MarkdownHighlighter()
        var lastText: String?
        var lastHighlight: NSRange?
    }
}
