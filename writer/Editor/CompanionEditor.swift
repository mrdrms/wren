import AppKit
import SwiftUI

private struct CompanionStyle: Equatable {
    let themeID: String
    let font: EditorFontChoice
    let fontSize: Double
    let lineHeight: Double
    let liveFormatting: Bool
}

/// The second editor's text view. Same look as the main editor, without the writing aids
/// (focus, typewriter, flow lock, slash menu), which belong to the sheet you're writing.
struct CompanionEditor: NSViewRepresentable {
    let sheet: CompanionSheet
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(sheet: sheet) }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = WrenTextView(usingTextLayoutManager: false)
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = true
        textView.usesFindBar = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.lineWidth = 620
        textView.imageFolder = sheet.url.deletingLastPathComponent()
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        context.coordinator.highlighter.imageSize = { [weak textView] in textView?.previewSize(forPath: $0) }
        textView.onImagesNeedRestyle = { [weak coordinator = context.coordinator] in coordinator?.restyle() }

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView

        context.coordinator.textView = textView
        model.companionEditor = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let prefs = model.prefs
        let style = CompanionStyle(themeID: prefs.themeID, font: prefs.theme.font ?? prefs.font, fontSize: prefs.fontSize,
                                   lineHeight: prefs.lineHeight, liveFormatting: prefs.liveFormatting)
        context.coordinator.apply(style)
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate {
        let sheet: CompanionSheet
        weak var textView: WrenTextView?
        let highlighter = MarkdownHighlighter()
        private var style: CompanionStyle?
        private var loaded = false

        init(sheet: CompanionSheet) { self.sheet = sheet }

        fileprivate func apply(_ style: CompanionStyle) {
            guard style != self.style, let textView else { return }
            self.style = style
            let theme = Theme.named(style.themeID)
            highlighter.theme = theme
            highlighter.fontChoice = style.font
            highlighter.fontSize = style.fontSize
            highlighter.lineHeight = style.lineHeight
            highlighter.plain = !style.liveFormatting
            textView.insertionPointColor = theme.accent
            textView.selectedTextAttributes = [.backgroundColor: theme.accent.withAlphaComponent(theme.isDark ? 0.35 : 0.22)]
            textView.linkTextAttributes = [.foregroundColor: theme.accent, .cursor: NSCursor.pointingHand]
            textView.typingAttributes = highlighter.baseAttributes
            textView.showsMediaPreviews = style.liveFormatting
            if !loaded {
                loaded = true
                textView.string = sheet.text // highlighted by the storage delegate
                textView.undoManager?.removeAllActions()
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            } else {
                restyle()
            }
            textView.layoutImagePreviews()
        }

        func restyle() {
            guard let textView, let storage = textView.textStorage else { return }
            highlighter.highlightAll(storage)
            textView.layoutImagePreviews()
        }

        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated {
                highlighter.highlight(textStorage, editedRange: editedRange)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            sheet.textDidChange(textView.string)
        }
    }
}
