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
