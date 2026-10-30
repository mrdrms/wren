import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import writer

struct DrawingTests {
    private func stroke(_ points: [(Double, Double)], tool: InkTool = .pen, size: Double = 3.5) -> InkStroke {
        InkStroke(tool: tool, color: .ink, size: size,
                  points: points.enumerated().map { InkPoint(x: $1.0, y: $1.1, pressure: 0.6, time: Double($0) / 60) })
    }

    private func draw(_ editor: InkEditor, from: CGPoint, to: CGPoint, steps: Int = 12) {
        editor.begin(at: from, pressure: nil, time: 0)
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            editor.move(to: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), pressure: nil, time: t)
        }
        editor.end()
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("wren-drawing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    @Test func drawingRoundTripsThroughItsFile() throws {
        var drawing = WrenDrawing()
        drawing.strokes = [stroke([(10, 10), (200, 120), (400, 90)]), stroke([(50, 600)], tool: .marker)]
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = DrawingFiles.newImageURL(in: folder)
        try DrawingFiles.save(drawing, image: image)

        #expect(DrawingFiles.isEditable(image))
        #expect(try DrawingFiles.load(image: image) == drawing)
    }

    @Test func savedPictureIsAFullResolutionPNG() throws {
        var drawing = WrenDrawing()
        drawing.strokes = [stroke([(100, 100), (1100, 700)])]
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("sketch.png")
        try DrawingFiles.save(drawing, image: image, scale: 2)

        let source = try #require(CGImageSourceCreateWithURL(image as CFURL, nil))
        let picture = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        #expect(picture.width == 2400)
        #expect(picture.height == 1600)
    }

    @Test func picturesWithoutStrokesAreNotEditable() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let photo = folder.appendingPathComponent("photo.png")
        try Data([0x89, 0x50]).write(to: photo)
        #expect(!DrawingFiles.isEditable(photo))
    }

    @Test func newNamesNeverOverwriteAnExistingDrawing() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = DrawingFiles.newImageURL(in: folder, now: now)
        try Data().write(to: first)
        let second = DrawingFiles.newImageURL(in: folder, now: now)
        #expect(first != second)
        // A leftover strokes file alone also reserves its name.
        try Data().write(to: DrawingFiles.sidecar(for: second))
        #expect(DrawingFiles.newImageURL(in: folder, now: now) != second)
    }

    @Test func newerFilesAreRefusedRatherThanMisread() throws {
        var drawing = WrenDrawing()
        drawing.version = WrenDrawing.currentVersion + 1
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = folder.appendingPathComponent("future.png")
        try JSONEncoder().encode(drawing).write(to: DrawingFiles.sidecar(for: image))
        #expect(throws: DrawingError.self) { try DrawingFiles.load(image: image) }
    }

    @Test func aStrokeIsCommittedAndUndoable() {
        let editor = InkEditor()
        draw(editor, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 500, y: 300))
        #expect(editor.drawing.strokes.count == 1)
        #expect(editor.hasChanges)
        #expect(editor.canUndo)

        editor.undo()
        #expect(editor.drawing.isEmpty)
        #expect(!editor.hasChanges)
        editor.redo()
        #expect(editor.drawing.strokes.count == 1)
    }

    @Test func simulatedPressureStaysInRange() {
        let editor = InkEditor()
        editor.begin(at: .zero, pressure: nil, time: 0)
        for i in 1...40 { editor.move(to: CGPoint(x: Double(i * i), y: 0), pressure: nil, time: Double(i) / 120) }
        let pressures = editor.live?.points.map(\.pressure) ?? []
        #expect(pressures.count > 10)
        #expect(pressures.allSatisfy { $0 >= 0.2 && $0 <= 1 })
        // Speeding up thins the line.
        #expect(pressures.last! < pressures[2])
    }

    @Test func eraserRemovesWhatItTouchesAndUndoRestoresItInPlace() {
        let editor = InkEditor()
        draw(editor, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 500, y: 100))
        draw(editor, from: CGPoint(x: 100, y: 400), to: CGPoint(x: 500, y: 400))
        draw(editor, from: CGPoint(x: 100, y: 700), to: CGPoint(x: 500, y: 700))
        let before = editor.drawing.strokes

        editor.tool = .eraser
        draw(editor, from: CGPoint(x: 300, y: 380), to: CGPoint(x: 300, y: 420))
        #expect(editor.drawing.strokes.count == 2)
        #expect(!editor.drawing.strokes.contains { $0.id == before[1].id })

        editor.undo()
        #expect(editor.drawing.strokes == before)
        editor.redo()
        #expect(editor.drawing.strokes.count == 2)
    }

    @Test func clearIsUndoable() {
        let editor = InkEditor()
        draw(editor, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 90))
        editor.clear()
        #expect(editor.drawing.isEmpty)
        editor.undo()
        #expect(editor.drawing.strokes.count == 1)
    }

    @Test func aNewStrokeClearsRedo() {
        let editor = InkEditor()
        draw(editor, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 90, y: 90))
        editor.undo()
        #expect(editor.canRedo)
        draw(editor, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 80, y: 30))
        #expect(!editor.canRedo)
    }

    @Test func viewportFitsAndMapsBack() {
        let viewport = InkViewport(drawingSize: CGSize(width: 1200, height: 800), in: CGRect(x: 0, y: 0, width: 600, height: 600))
        #expect(abs(viewport.scale - 0.5) < 0.0001)
        let center = viewport.toDrawing(CGPoint(x: 300, y: 300))
        #expect(abs(center.x - 600) < 0.001 && abs(center.y - 400) < 0.001)
    }

    @Test func brushTipsTaper() {
        let samples = InkRenderer.smoothed(stroke((0..<30).map { (Double($0) * 10, 100) }, tool: .brush))
        let middle = samples[samples.count / 2].width
        #expect(samples.first!.width < middle)
        #expect(samples.last!.width < middle)
    }
}

struct MediaSizeTests {
    @Test func widthsAreReadFromTheEndOfTheAltText() {
        #expect(MarkdownImage.split(alt: "Sketch|60%") == ("Sketch", .percent(60)))
        #expect(MarkdownImage.split(alt: "Sketch | 300") == ("Sketch ", .points(300)))
        #expect(MarkdownImage.split(alt: "|40%") == ("", .percent(40)))
        #expect(MarkdownImage.split(alt: "Just a caption") == ("Just a caption", nil))
        // A pipe in the middle of a caption isn't a size.
        #expect(MarkdownImage.split(alt: "This | that").width == nil)
        // Out-of-range percentages are kept sensible.
        #expect(MarkdownImage.split(alt: "x|250%").width == .percent(100))
        #expect(MarkdownImage.split(alt: "x|0%").width == nil)
    }

    @Test func widthsAreWrittenBackTheSameWay() {
        #expect(MarkdownImage.alt(caption: "Sketch", width: .percent(45)) == "Sketch|45%")
        #expect(MarkdownImage.alt(caption: "Sketch", width: nil) == "Sketch")
    }

    @Test func rawMarkdownTargetsGetCleanAltText() {
        let text = "Intro\n\n![Sketch|60%](assets/a.png)\n\n![Photo](b.jpg)\n"
        #expect(MarkdownImage.withoutSizes(text) == "Intro\n\n![Sketch](assets/a.png)\n\n![Photo](b.jpg)\n")
    }

    @Test func htmlKeepsTheWidthAndTheCaption() {
        let html = MarkdownHTML.convert("![Sketch|60%](assets/a.png)")
        #expect(html.contains("alt=\"Sketch\""))
        #expect(html.contains("style=\"width: 60%\""))
        #expect(!html.contains("|60%"))
        #expect(!MarkdownHTML.convert("![Photo](b.jpg)").contains("width"))
    }

    @Test func printGetsFixedWidths() {
        let html = Exporter.fixedWidths(MarkdownHTML.convert("![Sketch|50%](a.png)"), column: 400)
        #expect(html.contains("width=\"200\""))
        #expect(!html.contains("data-wren-width"))
    }

    @Test func resolvedWidthsStayInTheColumn() {
        #expect(MarkdownImage.Width.percent(50).resolved(in: 600) == 300)
        #expect(MarkdownImage.Width.points(900).resolved(in: 600) == 600)
    }
}
