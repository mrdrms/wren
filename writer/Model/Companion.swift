import Foundation
import Observation

/// The sheet in the second editor, open beside the one you're writing: an outline, a
/// character, an earlier draft. Lighter than the main document: it saves itself, but it
/// doesn't feed goals, history or the writing log.
@Observable
final class CompanionSheet {
    private(set) var url: URL
    private(set) var text: String

    @ObservationIgnored private let library: LibraryStore
    @ObservationIgnored private var dirty = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init?(url: URL, library: LibraryStore) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        self.url = url
        self.text = text
        self.library = library
    }

    var title: String {
        LibraryStore.titleAndPreview(text: text, fallback: url.deletingPathExtension().lastPathComponent).0
    }

    var words: Int { TextStats.contentWords(text) }

    func textDidChange(_ newText: String) {
        text = newText
        dirty = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Returns false if the write failed.
    @discardableResult
    func saveNow() -> Bool {
        saveTask?.cancel()
        guard dirty else { return true }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            dirty = false
            library.updateSheet(at: url, text: text)
            return true
        } catch {
            return false
        }
    }

    /// The file was renamed or moved while open.
    func moved(to newURL: URL) { url = newURL }
}
