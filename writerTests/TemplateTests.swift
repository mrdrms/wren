import Foundation
import Testing
@testable import writer

@MainActor
struct TemplateTests {
    private func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("wren-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func rendersPlaceholders() {
        let date = DateComponents(calendar: .current, year: 2026, month: 10, day: 25).date!
        let blog = Templates.render(Templates.blogPost.body, title: "Say \"hi\"", date: date)
        #expect(blog.hasPrefix("---\ntitle: \"Say \\\"hi\\\"\"\ndate: 2026-10-25\n"))
        #expect(FrontMatter.fields(blog)["title"] == "Say \"hi\"")
        #expect(Templates.render(Templates.chapter.body, title: "", chapter: 7).hasPrefix("# Chapter 7"))
        #expect(!Templates.render(Templates.journal.body, title: "", date: date).contains("{{"))
    }

    @Test func templateGuidanceIsNotContent() {
        // Guidance lives in margin notes, so a fresh template counts (almost) no words.
        let essay = Templates.render(Templates.essay.body, title: "Why We Write")
        #expect(TextStats.contentWords(essay) < 20)
        #expect(!MarkdownHTML.convert(Ghost.clean(essay)).contains("thesis"))
    }

    @Test func chapterNumbersAndNames() {
        let url = URL(fileURLWithPath: "/book/03 - The Storm.md")
        #expect(Chapters.number(of: url) == 3)
        #expect(Chapters.baseName(of: url) == "The Storm")
        #expect(Chapters.baseName(of: URL(fileURLWithPath: "/book/Prologue.md")) == "Prologue")
        #expect(Chapters.fileName(number: 4, base: "The Calm") == "04 The Calm.md")
    }

    @Test func createsProjectsAndRenumbersChapters() throws {
        let root = try tempFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = LibraryStore()
        let novel = Templates.projects.first { $0.id == "novel" }!
        let folder = try library.createProject(novel, name: "My Novel", author: "Ada", goal: 90_000, in: root)

        #expect(ProjectInfo.load(from: folder) == ProjectInfo(kind: .book, goal: 90_000, author: "Ada"))
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".md") }.sorted()
        #expect(files == ["01 Chapter One.md", "02 Chapter Two.md", "03 Chapter Three.md"])
        #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Notes/Outline.md").path))

        // Swap chapters one and three.
        let one = folder.appendingPathComponent("01 Chapter One.md")
        let two = folder.appendingPathComponent("02 Chapter Two.md")
        let three = folder.appendingPathComponent("03 Chapter Three.md")
        let moves = try library.renumberChapters([three, two, one])
        #expect(moves[three]?.lastPathComponent == "01 Chapter Three.md")
        #expect(moves[one]?.lastPathComponent == "03 Chapter One.md")
        #expect(moves[two] == nil)
        let first = try String(contentsOf: folder.appendingPathComponent("01 Chapter Three.md"), encoding: .utf8)
        #expect(first.hasPrefix("# Chapter 3"))
    }
}
