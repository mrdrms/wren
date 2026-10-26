import AppKit
import Foundation

/// An AI request shown to you before it's sent.
struct AIPending: Identifiable {
    let id = UUID()
    let title: String
    let provider: AIProvider
    let model: String
    /// Exactly what goes to the service.
    let preview: String
    let send: () -> Void
}

struct AIResult: Equatable {
    let title: String
    let markdown: String
    /// Where "Save as Sheet" puts it, for results worth keeping (a synopsis).
    var saveIn: URL?
}

extension AppModel {
    // MARK: AI editor

    /// The book folder the open sheet belongs to, if it's in one.
    var currentBook: URL? {
        guard let folder = loadedURL?.deletingLastPathComponent(), library.projects[folder]?.kind == .book else { return nil }
        return folder
    }

    /// Every AI request goes through here: off unless enabled, and shown to you first unless
    /// you've said not to ask.
    private func ask(_ title: String, system: String, prompt: String, previewText: String? = nil,
                     effort: String = "medium", image: (data: Data, mime: String)? = nil,
                     done: @escaping (String) -> Void) {
        guard prefs.aiEnabled else {
            showToast("Turn on the AI editor in Settings → AI", symbol: "sparkle")
            return
        }
        guard aiBusy == nil else {
            showToast("The AI editor is still working on \(aiBusy ?? "something")", symbol: "hourglass")
            return
        }
        // Keys, tokens and passwords in the text shouldn't go to an AI service any more than to a blog.
        guard confirmNoSecrets(action: "Send", in: prompt) else { return }
        let client = AIClient(provider: prefs.aiProvider, model: prefs.aiModel, effort: effort)
        let run = { [weak self] in
            guard let self else { return }
            self.aiBusy = title
            Task { @MainActor in
                defer { self.aiBusy = nil }
                do {
                    done(try await client.complete(system: system, prompt: prompt, image: image))
                } catch {
                    self.showToast(error.localizedDescription, symbol: "exclamationmark.triangle.fill")
                }
            }
        }
        if prefs.aiConfirmRequests {
            aiPending = AIPending(title: title, provider: client.provider, model: client.model,
                                  preview: previewText ?? "Instructions:\n\(system)\n\n\(prompt)", send: run)
        } else {
            run()
        }
    }

    private func showResult(_ title: String, _ markdown: String, saveIn: URL? = nil) {
        aiResult = AIResult(title: title, markdown: markdown, saveIn: saveIn)
        inspectorTab = .ai
        showInspector = true
    }

    /// Suggestions for the selected passage, added as margin notes beside the words they're about.
    func aiLineEdit() {
        guard let editor, let url = loadedURL else { return }
        let range = editor.selectedRange()
        let passage = (editor.string as NSString).substring(with: range)
        guard passage.split(whereSeparator: \.isWhitespace).count >= 5 else {
            showToast("Select a passage first, at least a sentence", symbol: "text.cursor")
            return
        }
        let request = AIEditor.lineEditPrompt(Ghost.clean(passage))
        ask("Line edit", system: request.system, prompt: request.prompt) { [weak self] answer in
            guard let self, let editor = self.editor, self.loadedURL == url else { return }
            let edits = AIEditor.parseLineEdits(answer)
            // Only annotate if the passage is still exactly where it was.
            let ns = editor.string as NSString
            guard NSMaxRange(range) <= ns.length, ns.substring(with: range) == passage else {
                return self.showToast("The passage changed while the AI was reading it. Try again.", symbol: "arrow.clockwise")
            }
            let annotated = AIEditor.annotate(passage, with: edits)
            guard annotated.placed > 0 else { return self.showToast("No suggestions: this passage reads well", symbol: "checkmark.circle") }
            editor.replace(range, with: annotated.text)
            self.showToast("\(annotated.placed) suggestions added as margin notes. Delete any you don't want.", symbol: "text.bubble")
        }
    }

    func aiCritique() {
        guard loadedURL != nil else { return }
        let title = currentTitle // the answer is about this sheet, even if you've moved on
        let request = AIEditor.critiquePrompt(title: title, text: Ghost.clean(text))
        ask("Editor's read", system: request.system, prompt: request.prompt) { [weak self] answer in
            self?.showResult("Editor's read: \(title)", answer)
        }
    }

    func aiTitles() {
        guard loadedURL != nil else { return }
        let request = AIEditor.titlesPrompt(text: Ghost.clean(text))
        let title = currentTitle
        ask("Title ideas", system: request.system, prompt: request.prompt) { [weak self] answer in
            self?.showResult("Title ideas for \(title)", answer)
        }
    }

    private func bookChapters(_ folder: URL) -> [(title: String, text: String)] {
        saveNow()
        return library.chapters(in: folder).compactMap { sheet in
            (try? String(contentsOf: sheet.url, encoding: .utf8)).map { (sheet.title, FrontMatter.strip(Ghost.clean($0))) }
        }
    }

    func aiContinuity() {
        guard let book = currentBook else { return showToast("Open a chapter of a book to check its continuity", symbol: "book.closed") }
        let chapters = bookChapters(book)
        let request = AIEditor.continuityPrompt(book: bookTitle(book), chapters: chapters)
        let words = chapters.reduce(0) { $0 + TextStats.contentWords($1.text) }
        ask("Continuity check", system: request.system, prompt: request.prompt,
            previewText: "All \(chapters.count) chapters of “\(bookTitle(book))” (\(words.formatted()) words), with these instructions:\n\n\(request.system)\n\n\(request.prompt)",
            effort: "high") { [weak self] answer in
            guard let self else { return }
            self.showResult("Continuity: \(self.bookTitle(book))", answer)
        }
    }

    func aiSynopsis() {
        guard let book = currentBook else { return showToast("Open a chapter of a book to draft its synopsis", symbol: "book.closed") }
        let chapters = bookChapters(book)
        let request = AIEditor.synopsisPrompt(book: bookTitle(book), chapters: chapters)
        ask("Synopsis", system: request.system, prompt: request.prompt, effort: "high") { [weak self] answer in
            self?.showResult("Synopsis draft", answer, saveIn: book.appendingPathComponent("Notes", isDirectory: true))
        }
    }

    /// Fills in missing alt text for the sheet's local images.
    func aiAltText() {
        guard let url = loadedURL else { return }
        let folder = url.deletingLastPathComponent()
        let missing = MarkdownImage.references(in: text).filter { reference in
            reference.alt.trimmingCharacters(in: .whitespaces).isEmpty && MarkdownImage.kind(of: reference.path) == .image
                && MarkdownImage.resolve(reference.path, relativeTo: folder).map(Safety.isMediaFile) == true
        }
        guard !missing.isEmpty else { return showToast("Every image here already has alt text", symbol: "checkmark.circle") }
        let images = missing.prefix(12).compactMap { reference -> (path: String, data: Data, mime: String)? in
            guard let file = MarkdownImage.resolve(reference.path, relativeTo: folder), let data = try? Data(contentsOf: file),
                  let image = NSImage(data: data), let png = image.pngData(maxSide: 1568) else { return nil }
            return (reference.path, png, "image/png")
        }
        guard !images.isEmpty else { return showToast("Couldn't read those images", symbol: "exclamationmark.triangle.fill") }
        let preview = "\(images.count) image\(images.count == 1 ? "" : "s") from this sheet, one request each:\n"
            + images.map { "• \($0.path)" }.joined(separator: "\n") + "\n\nwith: \(AIEditor.altTextPrompt.prompt)"
        // One confirmation covers every image.
        ask("Alt text", system: AIEditor.altTextPrompt.system, prompt: AIEditor.altTextPrompt.prompt, previewText: preview,
            image: images.first.map { ($0.data, $0.mime) }) { [weak self] first in
            guard let self else { return }
            Task { @MainActor in
                var alts = [images[0].path: first]
                let client = AIClient(provider: self.prefs.aiProvider, model: self.prefs.aiModel)
                self.aiBusy = "Alt text"
                defer { self.aiBusy = nil }
                for image in images.dropFirst() {
                    alts[image.path] = try? await client.complete(system: AIEditor.altTextPrompt.system, prompt: AIEditor.altTextPrompt.prompt,
                                                                  image: (image.data, image.mime))
                }
                guard self.loadedURL == url, let editor = self.editor else { return }
                var updated = self.text
                for (path, alt) in alts {
                    let clean = alt.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "]", with: ")")
                        .replacingOccurrences(of: "\n", with: " ")
                    updated = updated.replacingOccurrences(of: "![](\(path))", with: "![\(clean)](\(path))")
                }
                guard updated != self.text else { return }
                editor.replaceAll(with: updated, keepSelection: true)
                self.showToast("Alt text added to \(alts.count) image\(alts.count == 1 ? "" : "s")", symbol: "photo")
            }
        }
    }

    func saveAIResult() {
        guard let result = aiResult, let folder = result.saveIn else { return }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = try library.createSheet(in: folder, named: result.title, text: "# \(result.title)\n\n\(result.markdown)\n")
            selectedSheet = url
            showToast("Saved as a sheet in \(folder.lastPathComponent)", symbol: "doc.badge.plus")
        } catch {
            showToast("Couldn't save the sheet", symbol: "exclamationmark.triangle.fill")
        }
    }

    // MARK: Publishing

    func beginPublish() {
        guard loadedURL != nil else { return }
        saveNow()
        guard confirmNoSecrets(action: "Publish") else { return }
        showPublish = true
    }
}

extension NSImage {
    /// PNG data, scaled down so the longest side is at most `maxSide` (AI services cap image size).
    func pngData(maxSide: CGFloat) -> Data? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let scale = min(1, maxSide / CGFloat(max(cg.width, cg.height)))
        let width = Int(CGFloat(cg.width) * scale), height = Int(CGFloat(cg.height) * scale)
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: scaled).representation(using: .png, properties: [:])
    }
}
