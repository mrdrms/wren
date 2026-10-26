import AppKit
import Testing
@testable import writer

@MainActor
struct BookLayoutTests {
    private func chapter(_ n: Int) -> String {
        let prose = "The rain had not stopped for three days, and Mara had stopped pretending she didn't hear the knocking. It came at night, always after the lamps were out, *soft* and patient, like someone who had all the time in the world. "
        return "# Chapter \(n)\n\n" + Array(repeating: prose + prose, count: 14).joined(separator: "\n\n") + "\n\n* * *\n\n" + prose
    }

    @Test func paginatesABookWithChaptersOnRightPages() throws {
        let book = BookTypesetter(title: "The Lighthouse Keeper", author: "Ada Lovelace",
                                  chapters: [chapter(1), chapter(2), chapter(3)], settings: BookSettings())
        #expect(book.pages.first.map { if case .title = $0.content { true } else { false } } == true)
        // Every chapter opens on an odd (right-hand) page.
        for page in book.pages {
            if case .text(_, _, true) = page.content { #expect(page.isRecto) }
        }
        #expect(book.pages.count > 6)
        let pdf = try #require(book.pdfData())
        #expect(pdf.count > 1000)
        try writePreview(book, name: "book")

    }

    @Test func singleSheetGetsMarginsAndPages() throws {
        let text = NSAttributedString(string: String(repeating: "A sheet exported to PDF needs real margins. ", count: 400),
                                      attributes: [.font: NSFont.systemFont(ofSize: 12)])
        let sheet = BookTypesetter(title: "Sheet", document: text, settings: BookSettings(trim: .a4, twoSided: false, chaptersOnRight: false,
                                                                                               titlePage: false, pageNumbers: true, runningHeads: false))
        #expect(sheet.pages.count >= 2)
        #expect(BookTypesetter.textWidth(for: BookSettings(trim: .a4)) < 595 - 120)
        try writePreview(sheet, name: "sheet")
    }

    private func writePreview(_ book: BookTypesetter, name: String) throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("wren-book-preview")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for page in book.pages.prefix(6) {
            let image = book.image(of: page)
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: folder.appendingPathComponent("\(name)-\(page.number).png"))
        }
    }
}

@MainActor
struct FileSafetyTests {
    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wren-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func openSheetsFollowTheirFolder() {
        let old = URL(fileURLWithPath: "/lib/Book")
        let new = URL(fileURLWithPath: "/lib/Novel")
        #expect(AppModel.relocated(URL(fileURLWithPath: "/lib/Book/01 One.md"), from: old, to: new)?.path == "/lib/Novel/01 One.md")
        #expect(AppModel.relocated(URL(fileURLWithPath: "/lib/Book/Notes/Outline.md"), from: old, to: new)?.path == "/lib/Novel/Notes/Outline.md")
        #expect(AppModel.relocated(old, from: old, to: new) == new)
        // A sibling whose name merely starts the same is not inside the folder.
        #expect(AppModel.relocated(URL(fileURLWithPath: "/lib/Book 2/x.md"), from: old, to: new) == nil)
    }

    @Test func movingToTheSameFolderOrRecasingKeepsTheName() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = LibraryStore()
        let sheet = folder.appendingPathComponent("chapter one.md")
        try "text".write(to: sheet, atomically: true, encoding: .utf8)

        #expect(try library.move(sheet, to: folder) == sheet)
        let renamed = try library.rename(sheet, to: "Chapter One")
        #expect(renamed.lastPathComponent == "Chapter One.md")
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Chapter One.md"])
    }

    @Test func failedRenumberLeavesNoChapterHidden() throws {
        let folder = try tempFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let library = LibraryStore()
        let one = folder.appendingPathComponent("01 One.md")
        let two = folder.appendingPathComponent("02 Two.md")
        try "1".write(to: one, atomically: true, encoding: .utf8)
        try "2".write(to: two, atomically: true, encoding: .utf8)
        // A folder squatting on a final name makes the second pass fail.
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("01 Two.md"), withIntermediateDirectories: false)

        #expect(throws: (any Error).self) { try library.renumberChapters([two, one]) }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(!names.contains { $0.hasPrefix(".wren-renumber") })
        #expect(names.contains("01 One.md") && names.contains("02 Two.md"))
    }
}
