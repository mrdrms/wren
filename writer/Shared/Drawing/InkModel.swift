import CoreGraphics
import Foundation

// Wren's drawings, shared by every device: the same strokes, tools, colors and files on
// Mac, iPad and iPhone, so a sketch started on one continues on another exactly as it was.
// Nothing here depends on AppKit or UIKit, or on the main thread: drawings can be
// loaded, saved and exported from anywhere.

/// One sample of the pen: where it was, how hard it pressed (0...1) and when (seconds).
nonisolated struct InkPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var pressure: Double
    var time: Double

    var cgPoint: CGPoint { CGPoint(x: x, y: y) }
}

nonisolated enum InkTool: String, Codable, CaseIterable, Identifiable {
    case pen, brush, marker, eraser

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pen: "Pen"
        case .brush: "Brush"
        case .marker: "Marker"
        case .eraser: "Eraser"
        }
    }

    var symbol: String {
        switch self {
        case .pen: "pencil.tip"
        case .brush: "paintbrush.pointed"
        case .marker: "highlighter"
        case .eraser: "eraser"
        }
    }

    /// Width of the line for a given size setting and pressure, in canvas points.
    func width(size: Double, pressure: Double) -> Double {
        let p = min(max(pressure, 0), 1)
        switch self {
        case .pen: return size * (0.7 + 0.3 * p)
        case .brush: return size * 3 * (0.3 + 0.7 * p)
        case .marker: return size * 4.5
        case .eraser: return size * 6
        }
    }

    /// How opaque the finished stroke is. Markers are see-through, like a highlighter.
    var opacity: Double {
        switch self {
        case .pen, .eraser: 1
        case .brush: 0.94
        case .marker: 0.38
        }
    }
}

/// An sRGB color stored as hex, so files read the same everywhere.
nonisolated struct InkColor: Codable, Equatable, Hashable {
    var hex: UInt32

    var red: Double { Double((hex >> 16) & 0xFF) / 255 }
    var green: Double { Double((hex >> 8) & 0xFF) / 255 }
    var blue: Double { Double(hex & 0xFF) / 255 }

    func cgColor(alpha: Double = 1) -> CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    /// The colors every Wren drawing offers, in order.
    static let palette: [InkColor] = [
        InkColor(hex: 0x1F1D1A), // sumi ink
        InkColor(hex: 0x6E6A64), // graphite
        InkColor(hex: 0xC8442A), // vermilion
        InkColor(hex: 0x3448A8), // indigo
        InkColor(hex: 0x1E7A6E), // teal
        InkColor(hex: 0xD49A1E), // ochre
    ]
    static let ink = palette[0]

    /// What the color is called, for tooltips and VoiceOver.
    var name: String {
        switch hex {
        case 0x1F1D1A: "Sumi Ink"
        case 0x6E6A64: "Graphite"
        case 0xC8442A: "Vermilion"
        case 0x3448A8: "Indigo"
        case 0x1E7A6E: "Teal"
        case 0xD49A1E: "Ochre"
        default: "Ink"
        }
    }
    /// The paper every drawing is made on, so it reads the same on light and dark pages.
    static let paper = InkColor(hex: 0xFBF9F4)
}

nonisolated struct InkStroke: Codable, Equatable, Identifiable {
    var id = UUID()
    var tool: InkTool
    var color: InkColor
    /// The size setting it was drawn with; the tool turns it into a width.
    var size: Double
    var points: [InkPoint]

    var bounds: CGRect {
        guard let first = points.first else { return .null }
        var rect = CGRect(origin: first.cgPoint, size: .zero)
        for p in points { rect = rect.union(CGRect(origin: p.cgPoint, size: .zero)) }
        let pad = tool.width(size: size, pressure: 1)
        return rect.insetBy(dx: -pad, dy: -pad)
    }
}

/// A drawing: a fixed-size sheet of paper and the strokes on it, oldest first.
nonisolated struct WrenDrawing: Codable, Equatable {
    static let currentVersion = 1
    static let standardSize = CGSize(width: 1200, height: 800)

    var version = WrenDrawing.currentVersion
    var width = Double(WrenDrawing.standardSize.width)
    var height = Double(WrenDrawing.standardSize.height)
    var background: InkColor? = .paper
    var strokes: [InkStroke] = []

    var size: CGSize { CGSize(width: width, height: height) }
    var isEmpty: Bool { strokes.isEmpty }
}

/// How drawings live on disk: a PNG that every exporter, blog and app understands, with
/// the editable strokes beside it in `<name>.wrendrawing`. Lose the strokes and the
/// picture still works everywhere; it just can't be edited any more.
nonisolated enum DrawingFiles {
    static let sidecarExtension = "wrendrawing"

    static func sidecar(for image: URL) -> URL {
        image.deletingPathExtension().appendingPathExtension(sidecarExtension)
    }

    static func isEditable(_ image: URL) -> Bool {
        image.isFileURL && image.pathExtension.lowercased() == "png"
            && FileManager.default.fileExists(atPath: sidecar(for: image).path)
    }

    /// Limits on what a drawing file may ask for. Drawings can arrive in shared folders, so
    /// a damaged or hostile file must not be able to exhaust memory or hang the app.
    static let maxFileBytes = 32 * 1024 * 1024
    static let maxCanvasSide = 8192.0
    static let maxStrokes = 20_000
    static let maxPoints = 2_000_000

    static func load(image: URL) throws -> WrenDrawing {
        let file = sidecar(for: image)
        let bytes = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard bytes <= maxFileBytes else { throw DrawingError.damaged }
        let drawing = try JSONDecoder().decode(WrenDrawing.self, from: Data(contentsOf: file))
        guard drawing.version <= WrenDrawing.currentVersion else { throw DrawingError.newerVersion }
        return try validated(drawing)
    }

    /// The drawing if it's within bounds, with any unusable points dropped.
    static func validated(_ drawing: WrenDrawing) throws -> WrenDrawing {
        guard drawing.width.isFinite, drawing.height.isFinite,
              (16...maxCanvasSide).contains(drawing.width), (16...maxCanvasSide).contains(drawing.height),
              drawing.strokes.count <= maxStrokes,
              drawing.strokes.reduce(0, { $0 + $1.points.count }) <= maxPoints
        else { throw DrawingError.damaged }
        var clean = drawing
        clean.strokes = drawing.strokes.compactMap { stroke in
            guard stroke.size.isFinite, stroke.size > 0 else { return nil }
            var stroke = stroke
            stroke.size = min(stroke.size, 50)
            stroke.points = stroke.points.compactMap { p in
                guard p.x.isFinite, p.y.isFinite, p.time.isFinite else { return nil }
                return InkPoint(x: p.x, y: p.y, pressure: p.pressure.isFinite ? min(max(p.pressure, 0), 1) : 0.6, time: p.time)
            }
            return stroke.points.isEmpty ? nil : stroke
        }
        return clean
    }

    /// Writes the picture first, then the strokes, each atomically.
    static func save(_ drawing: WrenDrawing, image: URL, scale: Double = 2) throws {
        let drawing = try validated(drawing)
        guard let png = InkRenderer.pngData(drawing, scale: scale) else { throw DrawingError.renderFailed }
        try png.write(to: image, options: .atomic)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(drawing).write(to: sidecar(for: image), options: .atomic)
    }

    /// A fresh, unused file name for a new drawing in a sheet's assets folder.
    static func newImageURL(in folder: URL, now: Date = .now) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = "drawing-\(formatter.string(from: now))"
        var candidate = folder.appendingPathComponent(base).appendingPathExtension("png")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path)
                || FileManager.default.fileExists(atPath: sidecar(for: candidate).path) {
            candidate = folder.appendingPathComponent("\(base)-\(n)").appendingPathExtension("png")
            n += 1
        }
        return candidate
    }
}

nonisolated enum DrawingError: LocalizedError {
    case renderFailed, newerVersion, damaged

    var errorDescription: String? {
        switch self {
        case .renderFailed: "The drawing couldn't be turned into a picture."
        case .newerVersion: "This drawing was made with a newer version of Wren."
        case .damaged: "This drawing's file is damaged or too large to open."
        }
    }
}
