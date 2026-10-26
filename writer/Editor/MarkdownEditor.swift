import AppKit
import SwiftUI

private struct EditorConfig: Equatable {
    let themeID: String
    let font: EditorFontChoice
    let fontSize: Double
    let lineHeight: Double
    let lineWidth: Double
    let focus: FocusLevel
    let typewriter: Bool
    let styleLens: Bool
    let keySounds: Bool
    let flowLock: Bool
    let rhythm: Bool
    let hideMarkup: Bool
    let liveFormatting: Bool
}

struct MarkdownEditor: NSViewRepresentable {
    let model: AppModel

    /// One editor for the app's lifetime: when the layout changes (Zen, preview alone) the same
    /// text view moves to its new place, keeping undo history, selection and scroll position.
    func makeCoordinator() -> Coordinator {
        if let existing = model.editorCoordinator { return existing }
        let coordinator = Coordinator(model: model)
        model.editorCoordinator = coordinator
        return coordinator
    }

    func makeNSView(context: Context) -> NSScrollView {
        if let scrollView = context.coordinator.scrollView {
            scrollView.removeFromSuperview()
            DispatchQueue.main.async { scrollView.window?.makeFirstResponder(scrollView.documentView) }
            return scrollView
        }
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
        textView.isIncrementalSearchingEnabled = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.textStorage?.delegate = context.coordinator
        textView.layoutManager?.delegate = context.coordinator

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.scrollView = scrollView
        textView.onCut = { [weak model] in model?.addCut($0) }
        textView.onDecorationsNeeded = { [weak coordinator = context.coordinator] in coordinator?.updateDecorations() }
        textView.onImportImages = { [weak model] in model?.importImages($0) ?? [] }
        textView.onImagesNeedRestyle = { [weak coordinator = context.coordinator] in coordinator?.restyleForImages() }
        context.coordinator.highlighter.imageSize = { [weak textView] in textView?.previewSize(forPath: $0) }
        textView.commandInterceptor = { [weak coordinator = context.coordinator] in coordinator?.interceptCommand($0) ?? false }
        model.editor = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let coordinator = context.coordinator
        let prefs = model.prefs
        let config = EditorConfig(themeID: prefs.themeID, font: prefs.theme.font ?? prefs.font, fontSize: prefs.fontSize,
                                  lineHeight: prefs.lineHeight, lineWidth: prefs.lineWidth, focus: prefs.focus,
                                  typewriter: prefs.typewriter, styleLens: prefs.styleLens, keySounds: prefs.keySounds,
                                  flowLock: prefs.flowLock, rhythm: prefs.rhythm,
                                  hideMarkup: prefs.liveFormatting && prefs.hideMarkup, liveFormatting: prefs.liveFormatting)
        if config != coordinator.config {
            coordinator.apply(config)
        }
        if model.loadToken != coordinator.loadToken {
            coordinator.loadToken = model.loadToken
            coordinator.load(model.text)
        }
        if let jump = model.jumpRequest, jump.id != coordinator.lastJump {
            coordinator.lastJump = jump.id
            coordinator.jump(to: jump.range)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate, NSTextStorageDelegate, NSLayoutManagerDelegate {
        let model: AppModel
        weak var textView: WrenTextView?
        var scrollView: NSScrollView?
        fileprivate var config: EditorConfig?
        var loadToken = -1
        var lastJump: UUID?
        let highlighter = MarkdownHighlighter()
        private var isLoading = false
        private var restylePending = false
        private let slash = SlashMenuState()
        private var slashAnchor: Int?
        private var slashHost: NSView?
        private var bubbleHost: NSView?
        private var bubbleTask: Task<Void, Never>?

        init(model: AppModel) { self.model = model }

        fileprivate func apply(_ config: EditorConfig) {
            let previous = self.config
            self.config = config
            guard let textView else { return }
            let theme = Theme.named(config.themeID)
            highlighter.theme = theme
            highlighter.fontChoice = config.font
            highlighter.fontSize = config.fontSize
            highlighter.lineHeight = config.lineHeight

            textView.insertionPointColor = theme.accent
            textView.selectedTextAttributes = [.backgroundColor: theme.accent.withAlphaComponent(theme.isDark ? 0.35 : 0.22)]
            textView.linkTextAttributes = [.foregroundColor: theme.accent, .cursor: NSCursor.pointingHand]
            textView.typingAttributes = highlighter.baseAttributes
            textView.lineWidth = config.lineWidth
            textView.typewriter = config.typewriter
            textView.keySounds = config.keySounds
            textView.flowLock = config.flowLock
            textView.showRhythm = config.rhythm
            if !config.keySounds { KeySound.shared.stop() }

            highlighter.plain = !config.liveFormatting
            highlighter.hideMarkup = config.hideMarkup
            textView.showsMediaPreviews = config.liveFormatting
            if config.hideMarkup { highlighter.revealRange = currentParagraph() }
            let needsRestyle = previous == nil || previous!.themeID != config.themeID || previous!.font != config.font
                || previous!.fontSize != config.fontSize || previous!.lineHeight != config.lineHeight
                || previous!.hideMarkup != config.hideMarkup || previous!.liveFormatting != config.liveFormatting
            if needsRestyle, let storage = textView.textStorage {
                highlighter.highlightAll(storage)
                textView.layoutImagePreviews()
            }
            updateDecorations()
            centerCaret(animated: false)
        }

        func load(_ text: String) {
            guard let textView else { return }
            isLoading = true
            closeSlash()
            hideBubble()
            textView.imageFolder = model.loadedURL?.deletingLastPathComponent()
            highlighter.revealRange = NSRange(location: 0, length: 0)
            textView.string = text
            textView.layoutImagePreviews()
            isLoading = false
            textView.undoManager?.removeAllActions()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scrollToBeginningOfDocument(nil)
            updateDecorations()
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                self.centerCaret(animated: false)
            }
        }

        /// An image finished loading or the column width changed: re-measure and re-place previews.
        func restyleForImages() {
            guard !restylePending else { return }
            restylePending = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.textView, let storage = textView.textStorage else { return }
                self.restylePending = false
                self.highlighter.highlightAll(storage)
                textView.layoutImagePreviews()
            }
        }

        func jump(to requested: NSRange) {
            guard let textView else { return }
            // Outline and note ranges come from the last analysis, which trails typing by a
            // moment: after a deletion they can point past the end.
            let length = (textView.string as NSString).length
            let location = min(max(0, requested.location), length)
            let range = NSRange(location: location, length: min(max(0, requested.length), length - location))
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(range)
            if model.prefs.typewriter {
                centerCaret(animated: true)
            } else if let layout = textView.layoutManager, let container = textView.textContainer {
                let glyphs = layout.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = layout.boundingRect(forGlyphRange: glyphs, in: container)
                let y = max(0, rect.minY + textView.textContainerOrigin.y - 80)
                scroll(to: y, animated: true)
            }
            textView.showFindIndicator(for: NSRange(location: range.location, length: min(1, (textView.string as NSString).length - range.location)))
        }

        // MARK: Delegates

        nonisolated func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions,
                                     range editedRange: NSRange, changeInLength delta: Int) {
            guard editedMask.contains(.editedCharacters) else { return }
            MainActor.assumeIsolated {
                if highlighter.hideMarkup && !isLoading {
                    // Keep markup visible in the paragraph being typed in; multi-paragraph
                    // edits reveal nothing until the caret settles.
                    let ns = textStorage.string as NSString
                    let edited = NSIntersectionRange(editedRange, NSRange(location: 0, length: ns.length))
                    highlighter.revealRange = ns.substring(with: edited).contains("\n") ? nil : ns.paragraphRange(for: edited)
                }
                highlighter.highlight(textStorage, editedRange: editedRange)
            }
        }

        /// List dashes are drawn as round bullets while formatting marks are hidden.
        nonisolated func layoutManager(_ layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                                       properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                                       characterIndexes charIndexes: UnsafePointer<Int>, font aFont: NSFont,
                                       forGlyphRange glyphRange: NSRange) -> Int {
            MainActor.assumeIsolated {
                guard let storage = layoutManager.textStorage else { return 0 }
                let ns = storage.string as NSString
                var replaced: [CGGlyph]?
                for i in 0..<glyphRange.length {
                    let index = charIndexes[i]
                    guard index < ns.length else { continue }
                    let c = ns.character(at: index)
                    guard c == 45 || c == 42 || c == 43, storage.attribute(.wrenBullet, at: index, effectiveRange: nil) != nil else { continue }
                    let bullet = CGGlyph(clamping: aFont.glyph(withName: "bullet"))
                    guard bullet != 0 else { return 0 }
                    if replaced == nil { replaced = Array(UnsafeBufferPointer(start: glyphs, count: glyphRange.length)) }
                    replaced![i] = bullet
                }
                guard let replaced else { return 0 }
                layoutManager.setGlyphs(replaced, properties: props, characterIndexes: charIndexes, font: aFont, forGlyphRange: glyphRange)
                return glyphRange.length
            }
        }

        private func currentParagraph() -> NSRange? {
            guard let textView else { return nil }
            let ns = textView.string as NSString
            let selection = textView.selectedRange()
            let clamped = NSRange(location: min(selection.location, ns.length), length: min(selection.length, ns.length - min(selection.location, ns.length)))
            return ns.paragraphRange(for: clamped)
        }

        /// Shows the Markdown of the paragraph you're in, hides it everywhere else.
        private func updateReveal() {
            guard highlighter.hideMarkup, let textView, let storage = textView.textStorage, let paragraph = currentParagraph() else { return }
            let previous = highlighter.revealRange
            guard previous != paragraph else { return }
            highlighter.revealRange = paragraph
            let ns = storage.string as NSString
            var ranges = [paragraph]
            if let previous {
                ranges.append(NSIntersectionRange(previous, NSRange(location: 0, length: ns.length)))
            } else {
                ranges.append(NSRange(location: 0, length: ns.length)) // nothing was revealed: refresh around the caret
            }
            highlighter.restyleParagraphs(storage, around: ranges)
            textView.layoutImagePreviews()
        }

        /// What's active at the caret, for the format bar and selection bubble.
        private func updateFormatState() {
            guard let textView else { return }
            let string = textView.string
            let ns = string as NSString
            let selection = textView.selectedRange()
            guard selection.location <= ns.length else { return }
            let line = ns.lineRange(for: NSRange(location: selection.location, length: 0))
            var state = FormatState()
            state.block = BlockKind.of(line: ns.substring(with: line))
            func inside(_ regex: NSRegularExpression) -> Bool {
                regex.matches(in: string, range: line).contains { m in
                    selection.length > 0
                        ? selection.location >= m.range.location && NSMaxRange(selection) <= NSMaxRange(m.range)
                        : selection.location > m.range.location && selection.location < NSMaxRange(m.range)
                }
            }
            state.bold = inside(MarkdownHighlighter.bold)
            state.italic = inside(MarkdownHighlighter.italicStar) || inside(MarkdownHighlighter.italicUnderscore)
            state.strike = inside(MarkdownHighlighter.strike)
            state.highlight = inside(MarkdownHighlighter.mark)
            state.link = inside(MarkdownHighlighter.link)
            if model.formatState != state { model.formatState = state }
        }

        private func updateCaretFraction() {
            guard model.previewMode == .split, let textView else { return }
            let length = (textView.string as NSString).length
            model.caretFraction = length == 0 ? 0 : Double(textView.selectedRange().location) / Double(length)
        }

        func textDidChange(_ notification: Notification) {
            guard !isLoading, let textView else { return }
            updateCaretFraction()
            model.textDidChange(textView.string)
            updateDecorations()
            centerCaret(animated: true)
            hideBubble()
            updateSlash(afterTyping: true)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isLoading else { return }
            updateCaretFraction()
            updateReveal()
            updateFormatState()
            if config?.focus != .off { updateDecorations() }
            centerCaret(animated: true)
            updateSlash(afterTyping: false)
            scheduleBubble()
        }

        // MARK: Selection bubble

        private func scheduleBubble() {
            bubbleTask?.cancel()
            guard let textView, textView.selectedRange().length > 0, slashAnchor == nil else {
                hideBubble()
                return
            }
            // Wait for the selection to settle (mouse drags fire many changes).
            bubbleTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                self?.showBubble()
            }
        }

        private func showBubble() {
            guard let textView, let layout = textView.layoutManager, let container = textView.textContainer,
                  NSEvent.pressedMouseButtons == 0 else {
                if NSEvent.pressedMouseButtons != 0 { scheduleBubble() }
                return
            }
            let selection = textView.selectedRange()
            guard selection.length > 0, NSMaxRange(selection) <= (textView.string as NSString).length else { return hideBubble() }
            let host = bubbleHost ?? {
                let view = NSHostingView(rootView: AnyView(SelectionBubble().environment(model)))
                textView.addSubview(view)
                bubbleHost = view
                return view
            }()
            let size = host.fittingSize
            let glyphs = layout.glyphRange(forCharacterRange: selection, actualCharacterRange: nil)
            var lineGlyphs = NSRange()
            layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &lineGlyphs)
            let firstLine = layout.boundingRect(forGlyphRange: NSIntersectionRange(glyphs, lineGlyphs), in: container)
                .offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
            let visible = textView.visibleRect
            var origin = NSPoint(x: firstLine.midX - size.width / 2, y: firstLine.minY - size.height - 8)
            if origin.y < visible.minY + 4 {
                let whole = layout.boundingRect(forGlyphRange: glyphs, in: container).offsetBy(dx: textView.textContainerOrigin.x, dy: textView.textContainerOrigin.y)
                origin.y = whole.maxY + 8
            }
            origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
            host.frame = NSRect(origin: origin, size: size)
            if host.isHidden || host.alphaValue < 1 {
                host.alphaValue = 0
                host.isHidden = false
                NSAnimationContext.runAnimationGroup { $0.duration = 0.15; host.animator().alphaValue = 1 }
            }
        }

        private func hideBubble() {
            bubbleTask?.cancel()
            bubbleHost?.isHidden = true
        }

        // MARK: Slash menu

        /// "/" at the start of an empty line opens the insert menu; typing filters it.
        private func updateSlash(afterTyping: Bool) {
            guard let textView else { return }
            let ns = textView.string as NSString
            let selection = textView.selectedRange()
            let caret = selection.location
            if slashAnchor == nil {
                guard afterTyping, selection.length == 0, caret > 0, caret <= ns.length, ns.character(at: caret - 1) == 47 else { return }
                let lineStart = ns.lineRange(for: NSRange(location: caret - 1, length: 0)).location
                let before = ns.substring(with: NSRange(location: lineStart, length: caret - 1 - lineStart))
                guard before.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                slashAnchor = caret - 1
            }
            guard let anchor = slashAnchor, selection.length == 0, caret > anchor, anchor < ns.length, ns.character(at: anchor) == 47,
                  ns.lineRange(for: NSRange(location: anchor, length: 0)).location == ns.lineRange(for: NSRange(location: caret, length: 0)).location
            else { return closeSlash() }
            let query = ns.substring(with: NSRange(location: anchor + 1, length: caret - anchor - 1))
            guard !query.contains(" "), query.count <= 24 else { return closeSlash() }
            let items = SlashCatalog.filter(query)
            guard !items.isEmpty else { return closeSlash() }
            slash.items = items
            slash.selected = min(slash.selected, items.count - 1)
            if afterTyping { slash.selected = 0 }
            showSlash(at: anchor)
        }

        private func showSlash(at anchor: Int) {
            guard let textView, let layout = textView.layoutManager else { return }
            hideBubble()
            let host = slashHost ?? {
                let view = NSHostingView(rootView: AnyView(SlashMenuView(state: slash) { [weak self] in self?.chooseSlash($0) }.environment(model)))
                textView.addSubview(view)
                slashHost = view
                return view
            }()
            let glyph = min(layout.glyphIndexForCharacter(at: anchor), max(0, layout.numberOfGlyphs - 1))
            let line = layout.numberOfGlyphs == 0 ? layout.extraLineFragmentRect : layout.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let height = min(360, CGFloat(slash.items.count) * 46 + 34)
            let origin = textView.textContainerOrigin
            var frame = NSRect(x: origin.x + line.minX, y: origin.y + line.maxY + 4, width: 290, height: height)
            if frame.maxY > textView.visibleRect.maxY - 8 { frame.origin.y = origin.y + line.minY - height - 4 }
            host.frame = frame
            host.isHidden = false
            model.editorPopupOpen = true
        }

        private func closeSlash() {
            slashAnchor = nil
            slashHost?.isHidden = true
            if model.editorPopupOpen { model.editorPopupOpen = false }
        }

        private func chooseSlash(_ index: Int) {
            guard let textView, let anchor = slashAnchor, slash.items.indices.contains(index) else { return }
            let item = slash.items[index]
            let caret = textView.selectedRange().location
            closeSlash()
            textView.replace(NSRange(location: anchor, length: max(0, caret - anchor)), with: "")
            textView.setSelectedRange(NSRange(location: anchor, length: 0))
            item.run(model)
        }

        /// Arrow keys, Return and Esc drive the slash menu while it's open.
        func interceptCommand(_ selector: Selector) -> Bool {
            guard slashAnchor != nil, !(slashHost?.isHidden ?? true) else { return false }
            switch selector {
            case #selector(NSResponder.moveDown(_:)):
                slash.selected = min(slash.selected + 1, slash.items.count - 1)
            case #selector(NSResponder.moveUp(_:)):
                slash.selected = max(slash.selected - 1, 0)
            case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
                chooseSlash(slash.selected)
            case #selector(NSResponder.cancelOperation(_:)):
                closeSlash()
            default:
                return false
            }
            return true
        }

        // MARK: Focus mode & Style Lens

        /// Uses temporary attributes so the overlays never touch the document or undo stack.
        func updateDecorations() {
            guard let textView, let layout = textView.layoutManager, let config else { return }
            let ns = textView.string as NSString
            let full = NSRange(location: 0, length: ns.length)
            for key in [NSAttributedString.Key.foregroundColor, .backgroundColor, .underlineStyle, .underlineColor] {
                layout.removeTemporaryAttribute(key, forCharacterRange: full)
            }
            guard full.length > 0 else { return }
            let theme = Theme.named(config.themeID)

            if config.styleLens {
                for match in model.lensMatches where NSMaxRange(match.range) <= full.length {
                    let color = match.kind.color
                    layout.addTemporaryAttributes([
                        .backgroundColor: color.withAlphaComponent(theme.isDark ? 0.28 : 0.16),
                        .underlineStyle: NSUnderlineStyle.thick.rawValue,
                        .underlineColor: color.withAlphaComponent(0.8),
                    ], forCharacterRange: match.range)
                }
            }

            if let spoken = textView.spokenRange, NSMaxRange(spoken) <= full.length {
                layout.addTemporaryAttribute(.backgroundColor, value: theme.accent.withAlphaComponent(theme.isDark ? 0.45 : 0.3), forCharacterRange: spoken)
            }

            if config.focus != .off {
                let focus = focusRange(in: ns, level: config.focus, caret: textView.selectedRange().location)
                let dim = theme.text.withAlphaComponent(theme.isDark ? 0.22 : 0.2)
                if focus.location > 0 {
                    layout.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: NSRange(location: 0, length: focus.location))
                }
                let end = NSMaxRange(focus)
                if end < full.length {
                    layout.addTemporaryAttribute(.foregroundColor, value: dim, forCharacterRange: NSRange(location: end, length: full.length - end))
                }
            }
        }

        private func focusRange(in ns: NSString, level: FocusLevel, caret: Int) -> NSRange {
            let caret = min(caret, ns.length)
            let paragraph = ns.paragraphRange(for: NSRange(location: caret, length: 0))
            guard level == .sentence else { return paragraph }
            var result = paragraph
            ns.enumerateSubstrings(in: paragraph, options: .bySentences) { _, sentenceRange, enclosingRange, stop in
                if caret >= enclosingRange.location && caret <= NSMaxRange(enclosingRange) {
                    result = enclosingRange
                    // At a sentence boundary (just after the space), prefer the sentence being typed.
                    if caret < NSMaxRange(enclosingRange) || NSMaxRange(enclosingRange) == NSMaxRange(paragraph) { stop.pointee = true }
                }
            }
            return result
        }

        // MARK: Typewriter scrolling

        func centerCaret(animated: Bool) {
            guard let textView, textView.typewriter, let layout = textView.layoutManager, let container = textView.textContainer,
                  let scrollView = textView.enclosingScrollView else { return }
            let length = (textView.string as NSString).length
            let caret = min(textView.selectedRange().location, length)
            var lineRect: NSRect
            if caret >= length, !layout.extraLineFragmentRect.isEmpty {
                lineRect = layout.extraLineFragmentRect
            } else if layout.numberOfGlyphs > 0 {
                let glyph = min(layout.glyphIndexForCharacter(at: caret), layout.numberOfGlyphs - 1)
                lineRect = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            } else {
                lineRect = NSRect(x: 0, y: 0, width: container.size.width, height: highlighter.fontSize * highlighter.lineHeight)
            }
            let caretY = lineRect.midY + textView.textContainerOrigin.y
            let target = caretY - scrollView.contentSize.height / 2
            scroll(to: target, animated: animated)
        }

        private func scroll(to y: CGFloat, animated: Bool) {
            guard let textView, let scrollView = textView.enclosingScrollView else { return }
            let clip = scrollView.contentView
            let maxY = max(0, textView.frame.height - clip.bounds.height)
            let point = NSPoint(x: clip.bounds.origin.x, y: min(max(0, y), maxY))
            guard abs(point.y - clip.bounds.origin.y) > 0.5 else { return }
            if animated {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    clip.animator().setBoundsOrigin(point)
                }
            } else {
                clip.setBoundsOrigin(point)
            }
            scrollView.reflectScrolledClipView(clip)
        }
    }
}
