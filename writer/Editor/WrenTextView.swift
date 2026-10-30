import AppKit
import AVKit

/// The writing surface. Adds a centered measure, list continuation, Markdown shortcuts
/// and keystroke sounds on top of NSTextView.
final class WrenTextView: NSTextView {
    var lineWidth: CGFloat = 680 { didSet { updateInsets() } }
    var typewriter = false { didSet { updateInsets() } }
    var keySounds = false
    var flowLock = false
    var showRhythm = false { didSet { updateGutter() } }
    /// The word currently being read aloud.
    var spokenRange: NSRange? {
        didSet {
            onDecorationsNeeded?()
            if let spokenRange { scrollRangeToVisible(spokenRange) }
        }
    }
    var onCut: ((String) -> Void)?
    var onDecorationsNeeded: (() -> Void)?
    /// The sheet's folder, for resolving relative image paths.
    var imageFolder: URL?
    /// Inline image and video previews (live formatting only).
    var showsMediaPreviews = true {
        didSet { if showsMediaPreviews != oldValue { layoutImagePreviews() } }
    }
    var onImportImages: (([ImageSource]) -> [String])?
    var onImagesNeedRestyle: (() -> Void)?
    /// Double-clicking a drawing's picture opens it in the studio.
    var onEditDrawing: ((URL) -> Void)?
    private var imageViews: [PreviewImageView] = []
    private var suppressCutCapture = false

    private static let listPrefix = try! NSRegularExpression(pattern: "^([ \\t]*)(?:([-*+])|(\\d+)([.)]))[ \\t]+(\\[[ xX]\\][ \\t]+)?")
    private static let quotePrefix = try! NSRegularExpression(pattern: "^(>+[ \\t]?)")

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = newSize.width != frame.width
        super.setFrameSize(newSize)
        updateInsets()
        // Previews are sized to the column, so a narrower window means re-measuring them.
        if widthChanged, (string as NSString).range(of: "![").location != NSNotFound {
            onImagesNeedRestyle?()
        }
    }

    func updateInsets() {
        let visibleHeight = enclosingScrollView?.contentSize.height ?? 600
        let horizontal = max(40, (bounds.width - lineWidth) / 2)
        let top: CGFloat = typewriter ? visibleHeight / 2 : 40
        let inset = NSSize(width: horizontal.rounded(), height: top.rounded())
        if textContainerInset != inset { textContainerInset = inset }
        if showRhythm { updateGutter() }
    }

    override func layout() {
        super.layout()
        updateInsets()
    }

    // MARK: Sounds

    override func keyDown(with event: NSEvent) {
        if keySounds, !event.modifierFlags.contains(.command), !event.isARepeat {
            switch event.keyCode {
            case 36, 76: KeySound.shared.play(.enter)
            case 49: KeySound.shared.play(.space)
            case 51, 117: KeySound.shared.play(.delete)
            case 123...126: break // arrows
            default: KeySound.shared.play(.key)
            }
        }
        super.keyDown(with: event)
    }

    // MARK: Flow Lock

    override func deleteBackward(_ sender: Any?) {
        guard flowLock else { return super.deleteBackward(sender) }
        let selection = selectedRange()
        let edit = selection.length > 0
            ? Ghost.strike(string as NSString, range: selection)
            : Ghost.backspace(string as NSString, caret: selection.location)
        guard let edit else { return super.deleteBackward(sender) }
        apply(edit)
    }

    override func deleteWordBackward(_ sender: Any?) {
        guard flowLock, selectedRange().length == 0,
              let edit = Ghost.wordBackward(string as NSString, caret: selectedRange().location) else {
            return super.deleteWordBackward(sender)
        }
        apply(edit)
    }

    private func apply(_ edit: Ghost.Edit) {
        guard edit.range.length > 0 || !edit.replacement.isEmpty else { return }
        insertText(edit.replacement, replacementRange: edit.range)
        setSelectedRange(NSRange(location: edit.caret, length: 0))
    }

    // MARK: Cutting Room Floor

    /// Catches meaningful deletions (not undo, cut-to-move or reformatting) for the Cutting Room.
    override func shouldChangeText(in affectedCharRange: NSRange, replacementString: String?) -> Bool {
        let allowed = super.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        guard allowed, !suppressCutCapture, affectedCharRange.length >= 24,
              undoManager?.isUndoing != true, undoManager?.isRedoing != true else { return allowed }
        let removed = (string as NSString).substring(with: affectedCharRange)
        if !(replacementString ?? "").contains(removed) {
            onCut?(removed)
        }
        return allowed
    }

    override func cut(_ sender: Any?) {
        suppressCutCapture = true
        super.cut(sender)
        suppressCutCapture = false
    }

    // MARK: Rhythm gutter

    private lazy var gutter: RhythmGutterView = {
        let view = RhythmGutterView()
        view.textView = self
        addSubview(view)
        return view
    }()

    private func updateGutter() {
        gutter.isHidden = !showRhythm
        guard showRhythm else { return }
        let frame = NSRect(x: 0, y: 0, width: textContainerOrigin.x, height: bounds.height)
        if gutter.frame != frame { gutter.frame = frame }
        gutter.needsDisplay = true
    }

    override func didChangeText() {
        super.didChangeText()
        if showRhythm { gutter.needsDisplay = true }
        layoutImagePreviews()
    }

    // MARK: Images & video

    override func paste(_ sender: Any?) {
        if insertMedia(from: .general) || pasteVideoLink() { return }
        // Formatted text from Docs, Word or the web keeps its headings, bold, links and lists.
        if let markdown = RichPaste.markdown(from: .general) {
            insertText(markdown, replacementRange: selectedRange())
            return
        }
        super.paste(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        guard !ImageImporter.mediaFileURLs(on: pasteboard).isEmpty else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        setSelectedRange(NSRange(location: characterIndexForInsertion(at: point), length: 0))
        window?.makeFirstResponder(self)
        return insertMedia(from: pasteboard)
    }

    /// Image or video files, or raw image data such as a screenshot, become linked media in `assets/`.
    @discardableResult
    func insertMedia(from pasteboard: NSPasteboard) -> Bool {
        var sources: [ImageSource] = ImageImporter.mediaFileURLs(on: pasteboard).map { .file($0) }
        if sources.isEmpty, pasteboard.string(forType: .string) == nil, let png = ImageImporter.pngData(from: pasteboard) {
            sources = [.data(png, ext: "png")]
        }
        guard !sources.isEmpty else { return false }
        insertImageSources(sources)
        return true
    }

    /// A YouTube link pasted on an empty line becomes an embedded video.
    private func pasteVideoLink() -> Bool {
        guard let pasted = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !pasted.contains(" "), !pasted.contains("\n"), MarkdownImage.youTubeID(pasted) != nil else { return false }
        let ns = string as NSString
        let selection = selectedRange()
        let line = ns.substring(with: ns.lineRange(for: selection)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.isEmpty || selection.length == (line as NSString).length else { return false }
        insertBlock("![Video](\(pasted))")
        return true
    }

    func insertImageSources(_ sources: [ImageSource]) {
        guard let snippets = onImportImages?(sources), !snippets.isEmpty else { return }
        insertBlock(snippets.joined(separator: "\n\n"))
    }

    private func previewImage(forPath path: String) -> NSImage? {
        let url: URL?
        if case .youtube(let id) = MarkdownImage.kind(of: path) {
            url = URL(string: "https://img.youtube.com/vi/\(id)/hqdefault.jpg")
        } else {
            url = MarkdownImage.resolve(path, relativeTo: imageFolder)
        }
        guard let url else { return nil }
        return ImagePreviewCache.shared.image(for: url) { [weak self] in self?.onImagesNeedRestyle?() }
    }

    /// The width media can grow to: the text column.
    var mediaColumn: CGFloat { max(160, textContainer?.size.width ?? lineWidth) }

    /// Display size for a preview: a width chosen in the alt text (`|60%`), or the natural
    /// size fitted to the text column and a max height. YouTube embeds are always 16:9.
    func previewSize(forPath path: String, alt: String = "") -> NSSize? {
        let column = mediaColumn
        let chosen = MarkdownImage.split(alt: alt).width.map { CGFloat($0.resolved(in: Double(column))) }
        var size: NSSize
        switch MarkdownImage.kind(of: path) {
        case .youtube:
            let width = chosen ?? min(column, 640)
            return NSSize(width: width.rounded(), height: (width * 9 / 16).rounded())
        case .video:
            guard let url = MarkdownImage.resolve(path, relativeTo: imageFolder),
                  let natural = ImagePreviewCache.shared.videoSize(for: url, onLoad: { [weak self] in self?.onImagesNeedRestyle?() })
            else { return nil }
            size = natural
        case .image:
            guard let image = previewImage(forPath: path) else { return nil }
            size = image.size
        }
        if let chosen, size.width > 0 {
            return NSSize(width: chosen.rounded(), height: (chosen * size.height / size.width).rounded())
        }
        if size.width > column { size = NSSize(width: column, height: size.height * column / size.width) }
        if size.height > 460 { size = NSSize(width: size.width * 460 / size.height, height: 460) }
        return NSSize(width: size.width.rounded(), height: size.height.rounded())
    }

    /// Places a preview under every image or video on its own line. The highlighter has
    /// already reserved the space with paragraph spacing, so the text flows around it.
    func layoutImagePreviews() {
        guard let layout = layoutManager else { return }
        let ns = string as NSString
        var usedImages = 0
        var usedHandles = 0
        var liveVideos = Set<URL>()
        if showsMediaPreviews, ns.range(of: "![").location != NSNotFound {
            for m in MarkdownImage.lineRegex.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
                let path = ns.substring(with: m.range(at: 2))
                let alt = ns.substring(with: m.range(at: 1))
                guard let size = previewSize(forPath: path, alt: alt) else { continue }
                let glyphs = layout.glyphRange(forCharacterRange: m.range, actualCharacterRange: nil)
                guard glyphs.length > 0 else { continue }
                let line = layout.lineFragmentUsedRect(forGlyphAt: NSMaxRange(glyphs) - 1, effectiveRange: nil)
                let frame = NSRect(x: textContainerOrigin.x, y: textContainerOrigin.y + line.maxY + 10, width: size.width, height: size.height)

                let kind = MarkdownImage.kind(of: path)
                if kind == .video, let url = MarkdownImage.resolve(path, relativeTo: imageFolder) {
                    let player = videoViews[url] ?? makeVideoView(url)
                    videoViews[url] = player
                    if player.frame != frame { player.frame = frame }
                    player.isHidden = false
                    liveVideos.insert(url)
                    placeResizeHandle(&usedHandles, media: player, frame: frame, altRange: m.range(at: 1), alt: alt)
                    continue
                }
                if usedImages == imageViews.count {
                    let view = PreviewImageView()
                    addMediaSubview(view)
                    imageViews.append(view)
                }
                let view = imageViews[usedImages]
                view.image = previewImage(forPath: path)
                if case .youtube(let id) = kind {
                    view.link = URL(string: "https://www.youtube.com/watch?v=\(id)")
                } else {
                    view.link = nil
                }
                // A drawing with its strokes beside it can be opened again and edited.
                if kind == .image, let onEditDrawing, MarkdownImage.isLocalRelative(path),
                   let url = MarkdownImage.resolve(path, relativeTo: imageFolder), DrawingFiles.isEditable(url) {
                    view.edit = { onEditDrawing(url) }
                } else {
                    view.edit = nil
                }
                if view.frame != frame { view.frame = frame }
                view.isHidden = false
                view.toolTip = view.link != nil ? "Open on YouTube" : view.edit != nil ? "Double-click to edit this drawing" : path
                usedImages += 1
                placeResizeHandle(&usedHandles, media: view, frame: frame, altRange: m.range(at: 1), alt: alt)
            }
        }
        for view in imageViews[usedImages...] { view.isHidden = true; view.image = nil; view.edit = nil }
        for handle in resizeHandles[usedHandles...] { handle.isHidden = true; handle.media = nil; handle.commit = nil }
        for (url, player) in videoViews where !liveVideos.contains(url) {
            player.player?.pause()
            player.removeFromSuperview()
            videoViews[url] = nil
        }
    }

    private var videoViews: [URL: AVPlayerView] = [:]
    private var resizeHandles: [MediaResizeHandle] = []

    /// A corner grip over a picture or video: drag it to choose the width, written back into
    /// the Markdown as a percentage of the column so it looks the same on every screen.
    private func placeResizeHandle(_ used: inout Int, media: NSView, frame: NSRect, altRange: NSRange, alt: String) {
        if used == resizeHandles.count {
            let handle = MediaResizeHandle()
            resizeHandles.append(handle)
        }
        let handle = resizeHandles[used]
        used += 1
        if handle.superview !== self { addSubview(handle) }
        handle.media = media
        handle.mediaFrame = frame
        handle.column = mediaColumn
        handle.isHidden = false
        handle.commit = { [weak self] percent in
            guard let self else { return }
            let ns = self.string as NSString
            // Only if the Markdown is still the one this handle was laid out for.
            guard NSMaxRange(altRange) <= ns.length, ns.substring(with: altRange) == alt else { return }
            let caption = MarkdownImage.split(alt: alt).caption
            self.replace(altRange, with: MarkdownImage.alt(caption: caption, width: .percent(percent)))
        }
    }

    private func makeVideoView(_ url: URL) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = AVPlayer(url: url)
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.wantsLayer = true
        view.layer?.cornerRadius = 10
        view.layer?.masksToBounds = true
        addMediaSubview(view)
        return view
    }

    /// Pictures and videos go beneath the resize grips, so a grip is never covered.
    private func addMediaSubview(_ view: NSView) {
        if let grip = resizeHandles.first(where: { $0.superview === self }) {
            addSubview(view, positioned: .below, relativeTo: grip)
        } else {
            addSubview(view)
        }
    }

    /// One bar per sentence in the left margin; its length is the sentence's word count.
    fileprivate func drawRhythm(in dirtyRect: NSRect) {
        guard let layout = layoutManager, let container = textContainer else { return }
        let origin = textContainerOrigin
        let maxWidth = min(96, origin.x - 28)
        guard maxWidth > 12 else { return }
        let ns = string as NSString
        let area = visibleRect.intersection(dirtyRect.insetBy(dx: 0, dy: -40)).offsetBy(dx: -origin.x, dy: -origin.y)
        let glyphs = layout.glyphRange(forBoundingRect: NSRect(x: 0, y: area.minY, width: container.size.width, height: area.height), in: container)
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        guard chars.length > 0 else { return }

        var lastLineY: CGFloat = -1
        var stack: CGFloat = 0
        ns.enumerateSubstrings(in: ns.paragraphRange(for: chars), options: .byParagraphs) { paragraph, range, _, _ in
            let trimmed = (paragraph ?? "").trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), !trimmed.hasPrefix("```"), !trimmed.hasPrefix("!["), !trimmed.isEmpty else { return }
            ns.enumerateSubstrings(in: range, options: .bySentences) { sentence, sentenceRange, _, _ in
                let words = TextStats.wordCount(sentence ?? "")
                guard words > 0 else { return }
                let glyph = layout.glyphIndexForCharacter(at: sentenceRange.location)
                let line = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                if line.minY == lastLineY { stack += 1 } else { stack = 0; lastLineY = line.minY }
                let width = max(4, min(CGFloat(words) * 3.2, maxWidth))
                let bar = NSRect(x: origin.x - 18 - width, y: origin.y + line.minY + line.height * 0.42 + stack * 6,
                                 width: width, height: 3.5)
                Rhythm.Bucket(words: words).color.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: bar, xRadius: 1.75, yRadius: 1.75).fill()
            }
        }
    }

    // MARK: List continuation

    override func insertNewline(_ sender: Any?) {
        let ns = string as NSString
        let selection = selectedRange()
        let lineStart = ns.lineRange(for: NSRange(location: selection.location, length: 0)).location
        let beforeCaret = NSRange(location: lineStart, length: selection.location - lineStart)
        let line = ns.substring(with: beforeCaret)
        let lineNS = line as NSString

        var prefix: String?
        var nextPrefix = ""
        if let m = Self.listPrefix.firstMatch(in: line, range: NSRange(location: 0, length: lineNS.length)) {
            prefix = lineNS.substring(with: m.range)
            let indent = lineNS.substring(with: m.range(at: 1))
            let task = m.range(at: 5).location != NSNotFound ? "[ ] " : ""
            if m.range(at: 2).location != NSNotFound {
                nextPrefix = indent + lineNS.substring(with: m.range(at: 2)) + " " + task
            } else {
                let number = (Int(lineNS.substring(with: m.range(at: 3))) ?? 0) + 1
                nextPrefix = indent + "\(number)" + lineNS.substring(with: m.range(at: 4)) + " " + task
            }
        } else if let m = Self.quotePrefix.firstMatch(in: line, range: NSRange(location: 0, length: lineNS.length)) {
            prefix = lineNS.substring(with: m.range)
            nextPrefix = prefix!
        }

        guard let prefix else {
            super.insertNewline(sender)
            return
        }
        if line.trimmingCharacters(in: .whitespaces) == prefix.trimmingCharacters(in: .whitespaces) {
            // Return on an empty item ends the list.
            insertText("", replacementRange: beforeCaret)
        } else {
            insertText("\n" + nextPrefix, replacementRange: selection)
        }
    }

    // MARK: Formatting

    func apply(_ action: FormatAction) {
        switch action {
        case .bold: toggleInline("**", MarkdownHighlighter.bold, contentGroup: 2)
        case .italic: toggleInline("*", MarkdownHighlighter.italicStar, contentGroup: 1)
        case .highlight: toggleInline("==", MarkdownHighlighter.mark, contentGroup: 1)
        case .strikethrough: toggleInline("~~", MarkdownHighlighter.strike, contentGroup: 1)
        case .code: toggleInline("`", MarkdownHighlighter.inlineCode, contentGroup: nil)
        case .link: break // handled by the model's link sheet
        case .heading(let level): setBlock(String(repeating: "#", count: level) + " ")
        case .quote: setBlock("> ")
        case .bullet: setBlock("- ")
        case .numbered: setBlock("1. ")
        case .task: setBlock("- [ ] ")
        case .paragraph: setBlock("")
        case .divider: insertBlock("---")
        case .codeBlock:
            let selection = selectedRange()
            let selected = (string as NSString).substring(with: selection)
            insertBlock("```\n" + selected + "\n```")
            if selected.isEmpty {
                // Put the caret on the empty line inside the fence.
                let fenceEnd = (string as NSString).range(of: "\n```", options: .backwards, range: NSRange(location: 0, length: selectedRange().location))
                if fenceEnd.location != NSNotFound { setSelectedRange(NSRange(location: fenceEnd.location, length: 0)) }
            }
        case .note:
            // A CriticMarkup margin note: invisible in exports, listed in the Outline.
            let selection = selectedRange()
            insertText("{>>  <<}", replacementRange: NSRange(location: NSMaxRange(selection), length: 0))
            setSelectedRange(NSRange(location: NSMaxRange(selection) + 4, length: 0))
        }
    }

    /// Bold, italic and friends behave like a word processor: toggling off works even when the
    /// markers are hidden, and with nothing selected the word under the caret is formatted.
    private func toggleInline(_ marker: String, _ regex: NSRegularExpression, contentGroup: Int?) {
        let ns = string as NSString
        var selection = selectedRange()
        let lineRange = ns.lineRange(for: selection)
        let m = (marker as NSString).length

        // Already formatted? Unwrap the span that contains the selection.
        for match in regex.matches(in: string, range: lineRange)
        where selection.location >= match.range.location && NSMaxRange(selection) <= NSMaxRange(match.range) {
            let inner = contentGroup.map { match.range(at: $0) } ?? NSRange(location: match.range.location + m, length: match.range.length - 2 * m)
            insertText(ns.substring(with: inner), replacementRange: match.range)
            setSelectedRange(NSRange(location: match.range.location, length: inner.length))
            return
        }

        if selection.length == 0 {
            let word = selectionRange(forProposedRange: selection, granularity: .selectByWord)
            if word.length > 0, ns.substring(with: word).contains(where: { $0.isLetter || $0.isNumber }) { selection = word }
        }
        // Keep spaces outside the markers: "**word** " not "**word **".
        var trimmed = selection
        while trimmed.length > 0, ns.character(at: trimmed.location) == 32 { trimmed.location += 1; trimmed.length -= 1 }
        while trimmed.length > 0, ns.character(at: NSMaxRange(trimmed) - 1) == 32 { trimmed.length -= 1 }
        let selected = ns.substring(with: trimmed)
        insertText(marker + selected + marker, replacementRange: trimmed)
        setSelectedRange(NSRange(location: trimmed.location + m, length: trimmed.length))
    }

    private static let blockPrefix = try! NSRegularExpression(pattern: "^(#{1,6} |> ?|[-*+] \\[[ xX]\\] |[-*+] |\\d+[.)] )")

    /// Sets the block style of every selected line in one undoable step. Applying the style
    /// the lines already have turns it off; an empty prefix makes them plain paragraphs.
    private func setBlock(_ prefix: String) {
        let ns = string as NSString
        let selection = selectedRange()
        let linesRange = ns.lineRange(for: selection)
        var block = ns.substring(with: linesRange)
        let trailingNewline = block.hasSuffix("\n")
        if trailingNewline { block.removeLast() }
        let lines = block.components(separatedBy: "\n")

        func existing(_ line: String) -> String {
            guard let m = Self.blockPrefix.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return "" }
            return (line as NSString).substring(with: m.range)
        }
        func sameKind(_ current: String) -> Bool {
            prefix == "1. " ? current.range(of: "^\\d+[.)] $", options: .regularExpression) != nil : current == prefix
        }
        let content = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let turnOff = prefix.isEmpty || (!content.isEmpty && content.allSatisfy { sameKind(existing($0)) })

        var number = 0
        let rebuilt = lines.map { line -> String in
            let body = String(line.dropFirst(existing(line).count))
            if turnOff || (lines.count > 1 && line.trimmingCharacters(in: .whitespaces).isEmpty) { return body }
            number += 1
            return (prefix == "1. " ? "\(number). " : prefix) + body
        }
        let result = rebuilt.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        insertText(result, replacementRange: linesRange)

        if lines.count == 1 {
            let delta = (rebuilt[0] as NSString).length - (lines[0] as NSString).length
            let lineStart = linesRange.location
            let firstPrefix = (rebuilt[0] as NSString).length - (lines[0] as NSString).length + (existing(lines[0]) as NSString).length
            let caret = max(lineStart + max(0, firstPrefix), selection.location + delta)
            setSelectedRange(NSRange(location: min(caret, (string as NSString).length), length: selection.length))
        } else {
            setSelectedRange(NSRange(location: linesRange.location, length: (result as NSString).length - (trailingNewline ? 1 : 0)))
        }
    }

    /// Inserts text as its own paragraph(s) at the caret.
    func insertBlock(_ block: String) {
        let ns = string as NSString
        let selection = selectedRange()
        let before = selection.location > 0 && ns.character(at: selection.location - 1) != 10 ? "\n\n" : ""
        let after = NSMaxRange(selection) < ns.length && ns.character(at: NSMaxRange(selection)) != 10 ? "\n\n" : "\n"
        insertText(before + block + after, replacementRange: selection)
    }

    /// One undoable replacement of an arbitrary range.
    func replace(_ range: NSRange, with text: String) {
        let length = (string as NSString).length
        let safe = NSRange(location: min(range.location, length), length: min(range.length, length - min(range.location, length)))
        insertText(text, replacementRange: safe)
    }

    // MARK: Keyboard & mouse helpers

    /// Lets a popup (the slash menu) take arrow keys, Return and Esc while it's open.
    var commandInterceptor: ((Selector) -> Bool)?

    override func doCommand(by selector: Selector) {
        if commandInterceptor?(selector) == true { return }
        super.doCommand(by: selector)
    }

    private static let checkbox = try! NSRegularExpression(pattern: "^[ \\t]*[-*+] (\\[[ xX]\\])", options: .anchorsMatchLines)

    /// Clicking a checklist box ticks it.
    override func mouseDown(with event: NSEvent) {
        if let layout = layoutManager, let container = textContainer, event.clickCount == 1 {
            let point = convert(event.locationInWindow, from: nil)
            let inContainer = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            var fraction: CGFloat = 0
            let index = layout.characterIndex(for: inContainer, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
            let ns = string as NSString
            if index < ns.length {
                let line = ns.lineRange(for: NSRange(location: index, length: 0))
                if let m = Self.checkbox.firstMatch(in: string, range: line), NSLocationInRange(index, m.range(at: 1)) {
                    let box = m.range(at: 1)
                    let checked = ns.substring(with: box).lowercased() == "[x]"
                    replace(box, with: checked ? "[ ]" : "[x]")
                    return
                }
            }
        }
        super.mouseDown(with: event)
    }

    /// Replaces the whole document as one undoable edit (restores, sweeps, reordering).
    func replaceAll(with text: String, keepSelection: Bool = false) {
        let selection = selectedRange()
        let visible = enclosingScrollView?.contentView.bounds.origin
        suppressCutCapture = true
        insertText(text, replacementRange: NSRange(location: 0, length: (string as NSString).length))
        suppressCutCapture = false
        if keepSelection, let visible {
            setSelectedRange(NSRange(location: min(selection.location, (string as NSString).length), length: 0))
            enclosingScrollView?.contentView.scroll(to: visible)
            enclosingScrollView?.reflectScrolledClipView(enclosingScrollView!.contentView)
        } else {
            setSelectedRange(NSRange(location: 0, length: 0))
            scrollRangeToVisible(NSRange(location: 0, length: 0))
        }
    }

    func insertAtCaret(_ text: String) {
        window?.makeFirstResponder(self)
        let selection = selectedRange()
        let ns = string as NSString
        // Drop it in as its own paragraph when the caret sits between paragraphs.
        let atLineStart = selection.location == 0 || ns.character(at: selection.location - 1) == 10
        insertText(atLineStart ? text + "\n" : text, replacementRange: selection)
    }
}

/// A transparent overlay for the margin, so the bars draw above the text view's own layers.
private final class RhythmGutterView: NSView {
    weak var textView: WrenTextView?
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { textView?.drawRhythm(in: dirtyRect) }
}

/// An inline image preview. Plain images never intercept clicks meant for the text;
/// YouTube previews show a play badge and open the video when clicked.
final class PreviewImageView: NSView {
    var image: NSImage? {
        didSet { if image !== oldValue { layer?.contents = image } }
    }
    var link: URL? {
        didSet { badge.isHidden = link == nil }
    }
    /// Set for drawings: a double-click opens them in the studio.
    var edit: (() -> Void)? {
        didSet {
            if (edit == nil) != (oldValue == nil) { window?.invalidateCursorRects(for: self) }
            if edit == nil { pencil.isHidden = true }
        }
    }
    private let badge = NSImageView()
    private let pencil = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspectFill
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.06).cgColor
        let config = NSImage.SymbolConfiguration(pointSize: 54, weight: .regular)
            .applying(.init(paletteColors: [.white, NSColor.black.withAlphaComponent(0.55)]))
        badge.image = NSImage(systemSymbolName: "play.circle.fill", accessibilityDescription: "Play")?.withSymbolConfiguration(config)
        badge.isHidden = true
        addSubview(badge)
        pencil.image = NSImage(systemSymbolName: "pencil.tip.crop.circle.fill", accessibilityDescription: "Edit drawing")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 22, weight: .regular)
                .applying(.init(paletteColors: [.white, NSColor.black.withAlphaComponent(0.55)])))
        pencil.isHidden = true
        addSubview(pencil)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        super.layout()
        badge.frame = NSRect(x: bounds.midX - 34, y: bounds.midY - 34, width: 68, height: 68)
        pencil.frame = NSRect(x: bounds.maxX - 36, y: bounds.maxY - 36, width: 28, height: 28)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        link == nil && edit == nil ? nil : (frame.contains(point) ? self : nil)
    }

    override func resetCursorRects() {
        if link != nil || edit != nil { addCursorRect(bounds, cursor: .pointingHand) }
    }

    override func mouseEntered(with event: NSEvent) {
        pencil.isHidden = edit == nil
    }

    override func mouseExited(with event: NSEvent) {
        pencil.isHidden = true
    }

    override func mouseDown(with event: NSEvent) {
        if let link {
            NSWorkspace.shared.open(link)
        } else if let edit, event.clickCount == 2 {
            edit()
        } else {
            // A single click on a drawing still places the caret, as it does on any picture.
            superview?.mouseDown(with: event)
        }
    }
}

/// The resize grip for one picture or video. It covers the whole column beside the media
/// (so the grip can be dragged wider than the picture is now) but only the grip itself takes
/// clicks; everything else passes through to the text.
final class MediaResizeHandle: NSView {
    weak var media: NSView?
    var mediaFrame: NSRect = .zero { didSet { if !dragging { layoutForMedia() } } }
    var column: CGFloat = 600 { didSet { if !dragging { layoutForMedia() } } }
    var commit: ((Int) -> Void)?

    private var hovering = false
    private var dragging = false
    private var dragStart: NSPoint = .zero
    private var startWidth: CGFloat = 0
    private var liveWidth: CGFloat = 0
    private var tracking: NSTrackingArea?
    private static let grip: CGFloat = 22

    override var isFlipped: Bool { true }

    private var aspect: CGFloat { mediaFrame.width > 0 ? mediaFrame.height / mediaFrame.width : 1 }
    private var currentWidth: CGFloat { dragging ? liveWidth : mediaFrame.width }
    private var gripRect: NSRect {
        NSRect(x: currentWidth - Self.grip + 6, y: currentWidth * aspect - Self.grip + 6, width: Self.grip, height: Self.grip)
    }

    private func layoutForMedia() {
        frame = NSRect(x: mediaFrame.minX, y: mediaFrame.minY, width: max(column, mediaFrame.width) + 8,
                       height: max(column, mediaFrame.width) * aspect + 8)
        updateTracking()
        needsDisplay = true
    }

    private func updateTracking() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: NSRect(x: 0, y: 0, width: mediaFrame.width + 8, height: mediaFrame.height + 8),
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, hovering || dragging else { return nil }
        return gripRect.contains(convert(point, from: superview)) ? self : nil
    }

    override func resetCursorRects() {
        removeAllToolTips()
        guard hovering else { return }
        addCursorRect(gripRect, cursor: .frameResize(position: .bottomRight, directions: .all))
        addToolTip(gripRect, owner: "Drag to resize. The size is kept as a share of the page width." as NSString, userData: nil)
    }

    override func mouseEntered(with event: NSEvent) {
        hovering = true
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        window?.invalidateCursorRects(for: self)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        dragStart = convert(event.locationInWindow, from: nil)
        startWidth = mediaFrame.width
        liveWidth = startWidth
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        // Follow whichever way the pointer moved further, so the corner tracks it.
        let byWidth = startWidth + (point.x - dragStart.x)
        let byHeight = startWidth + (point.y - dragStart.y) / max(aspect, 0.01)
        liveWidth = min(column, max(column * 0.1, abs(point.x - dragStart.x) > abs(point.y - dragStart.y) ? byWidth : byHeight))
        if let media {
            media.frame = NSRect(x: mediaFrame.minX, y: mediaFrame.minY, width: liveWidth.rounded(), height: (liveWidth * aspect).rounded())
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        // Snap to 5% steps: tidy numbers in the Markdown, and easy to match another picture.
        let percent = Int((liveWidth / max(column, 1) * 20).rounded()) * 5
        needsDisplay = true
        if abs(liveWidth - startWidth) >= 2 {
            commit?(min(100, max(10, percent)))
        } else {
            media?.frame = mediaFrame
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering || dragging else { return }
        let width = currentWidth, height = currentWidth * aspect
        if dragging {
            let outline = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: width - 1, height: height - 1), xRadius: 10, yRadius: 10)
            outline.lineWidth = 1.5
            outline.setLineDash([5, 4], count: 2, phase: 0)
            NSColor.controlAccentColor.setStroke()
            outline.stroke()
            let percent = Int((width / max(column, 1) * 20).rounded()) * 5
            let label = "\(min(100, max(10, percent)))%" as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white,
            ]
            let size = label.size(withAttributes: attributes)
            let pill = NSRect(x: width - size.width - 22, y: height - size.height - 18, width: size.width + 14, height: size.height + 6)
            NSColor.black.withAlphaComponent(0.65).setFill()
            NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
            label.draw(at: NSPoint(x: pill.minX + 7, y: pill.minY + 3), withAttributes: attributes)
        }
        // The grip: a white disc with two diagonal strokes, readable on any picture.
        let grip = gripRect.insetBy(dx: 3, dy: 3)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = 3
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: grip).fill()
        NSShadow().set()
        NSColor.black.withAlphaComponent(0.6).setStroke()
        for inset: CGFloat in [4.5, 8] {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: grip.maxX - inset, y: grip.maxY - 3.5))
            line.line(to: NSPoint(x: grip.maxX - 3.5, y: grip.maxY - inset))
            line.lineWidth = 1.3
            line.lineCapStyle = .round
            line.stroke()
        }
    }
}
