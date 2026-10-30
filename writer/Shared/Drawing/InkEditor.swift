import CoreGraphics
import Foundation
import Observation

/// Everything that happens while drawing, the same on every device: which tool, color and
/// size are in hand, the stroke being drawn, the eraser, and undo. The platform canvases
/// only report where the pen is; all the decisions are made here.
@Observable
final class InkEditor {
    static let sizes: [Double] = [2, 3.5, 6]

    private(set) var drawing: WrenDrawing
    /// The drawing as it was opened, to tell whether anything changed.
    let original: WrenDrawing
    var tool: InkTool = .pen
    var color: InkColor = .ink
    var size: Double = InkEditor.sizes[1]

    /// The stroke under the pen right now, and where the device expects it to go next.
    private(set) var live: InkStroke?
    private(set) var prediction: [InkPoint] = []
    private(set) var canUndo = false
    private(set) var canRedo = false

    /// Called whenever the finished strokes change, so a canvas can redraw its cache.
    @ObservationIgnored var onStrokesChanged: (() -> Void)?

    private enum Change {
        case add(InkStroke)
        /// Strokes the eraser removed, with the index each had when it went.
        case erase([(index: Int, stroke: InkStroke)])
        case clear([InkStroke])
    }
    @ObservationIgnored private var undoStack: [Change] = [] { didSet { canUndo = !undoStack.isEmpty } }
    @ObservationIgnored private var redoStack: [Change] = [] { didSet { canRedo = !redoStack.isEmpty } }
    @ObservationIgnored private var erasing: [(index: Int, stroke: InkStroke)] = []
    @ObservationIgnored private var lastEraserPoint: CGPoint?
    @ObservationIgnored private var simulatedPressure = 0.6

    init(drawing: WrenDrawing = WrenDrawing()) {
        self.drawing = drawing
        self.original = drawing
    }

    var hasChanges: Bool { drawing != original }

    // MARK: Pen

    /// `pressure` is nil for a mouse, trackpad or finger; the pen then reads it from speed.
    func begin(at point: CGPoint, pressure: Double?, time: TimeInterval) {
        cancel()
        if tool == .eraser {
            erasing = []
            lastEraserPoint = point
            erase(around: point)
            return
        }
        simulatedPressure = 0.6
        live = InkStroke(tool: tool, color: color, size: size,
                         points: [InkPoint(x: point.x, y: point.y, pressure: pressure ?? simulatedPressure, time: time)])
    }

    func move(to point: CGPoint, pressure: Double?, time: TimeInterval, predicted: [CGPoint] = []) {
        if tool == .eraser, let last = lastEraserPoint {
            // Sweep the gap so a quick swipe doesn't skip strokes.
            let gap = hypot(point.x - last.x, point.y - last.y)
            let steps = max(1, Int(gap / 4))
            for s in 1...steps {
                let t = Double(s) / Double(steps)
                erase(around: CGPoint(x: last.x + (point.x - last.x) * t, y: last.y + (point.y - last.y) * t))
            }
            lastEraserPoint = point
            return
        }
        guard var stroke = live, let last = stroke.points.last else { return }
        let distance = hypot(point.x - last.x, point.y - last.y)
        // Ignore jitter smaller than a hair.
        if distance >= 0.75 {
            let p = pressure ?? speedPressure(distance: distance, interval: time - last.time)
            stroke.points.append(InkPoint(x: point.x, y: point.y, pressure: p, time: time))
            live = stroke
        }
        let lastPressure = stroke.points.last?.pressure ?? 0.6
        prediction = predicted.map { InkPoint(x: $0.x, y: $0.y, pressure: lastPressure, time: time) }
    }

    func end() {
        prediction = []
        if tool == .eraser {
            if !erasing.isEmpty { record(.erase(erasing)) }
            erasing = []
            lastEraserPoint = nil
            return
        }
        guard let stroke = live else { return }
        live = nil
        drawing.strokes.append(stroke)
        record(.add(stroke))
        onStrokesChanged?()
    }

    /// Drops the stroke in progress (a gesture was interrupted).
    func cancel() {
        live = nil
        prediction = []
        if !erasing.isEmpty { record(.erase(erasing)) }
        erasing = []
        lastEraserPoint = nil
    }

    /// Slow, deliberate strokes press harder than quick flicks, eased so the line never jumps.
    private func speedPressure(distance: Double, interval: TimeInterval) -> Double {
        let speed = distance / max(interval, 1.0 / 240) // points per second
        let target = min(1, max(0.22, 1.08 - speed / 1600))
        simulatedPressure += (target - simulatedPressure) * 0.28
        return simulatedPressure
    }

    // MARK: Eraser

    private func erase(around point: CGPoint) {
        let radius = InkTool.eraser.width(size: size, pressure: 1) / 2
        var index = drawing.strokes.count - 1
        var removed = false
        while index >= 0 {
            let stroke = drawing.strokes[index]
            if Self.stroke(stroke, isWithin: radius, of: point) {
                erasing.append((index, stroke))
                drawing.strokes.remove(at: index)
                removed = true
            }
            index -= 1
        }
        if removed { onStrokesChanged?() }
    }

    static func stroke(_ stroke: InkStroke, isWithin radius: Double, of point: CGPoint) -> Bool {
        let reach = radius + stroke.tool.width(size: stroke.size, pressure: 1) / 2
        guard stroke.bounds.insetBy(dx: -radius, dy: -radius).contains(point) else { return false }
        let points = stroke.points
        if points.count == 1 { return hypot(points[0].x - point.x, points[0].y - point.y) <= reach }
        for i in 1..<points.count where distance(from: point, toSegment: points[i - 1].cgPoint, points[i].cgPoint) <= reach {
            return true
        }
        return false
    }

    private static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: Undo

    func clear() {
        cancel()
        guard !drawing.strokes.isEmpty else { return }
        record(.clear(drawing.strokes))
        drawing.strokes = []
        onStrokesChanged?()
    }

    func undo() {
        cancel()
        guard let change = undoStack.popLast() else { return }
        switch change {
        case .add(let stroke):
            drawing.strokes.removeAll { $0.id == stroke.id }
        case .erase(let removed):
            for item in removed.reversed() { drawing.strokes.insert(item.stroke, at: min(item.index, drawing.strokes.count)) }
        case .clear(let strokes):
            drawing.strokes = strokes
        }
        redoStack.append(change)
        onStrokesChanged?()
    }

    func redo() {
        cancel()
        guard let change = redoStack.popLast() else { return }
        switch change {
        case .add(let stroke):
            drawing.strokes.append(stroke)
        case .erase(let removed):
            let ids = Set(removed.map(\.stroke.id))
            drawing.strokes.removeAll { ids.contains($0.id) }
        case .clear:
            drawing.strokes = []
        }
        undoStack.append(change)
        onStrokesChanged?()
    }

    private func record(_ change: Change) {
        undoStack.append(change)
        redoStack = []
    }
}

/// Where the paper sits inside a canvas view: fitted to the view, centered, aspect kept.
struct InkViewport {
    let scale: Double
    let origin: CGPoint

    init(drawingSize: CGSize, in bounds: CGRect) {
        let scale = min(bounds.width / max(drawingSize.width, 1), bounds.height / max(drawingSize.height, 1))
        self.scale = max(scale, 0.0001)
        origin = CGPoint(x: bounds.midX - drawingSize.width * self.scale / 2, y: bounds.midY - drawingSize.height * self.scale / 2)
    }

    func toDrawing(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
    }

    func paperRect(for size: CGSize) -> CGRect {
        CGRect(x: origin.x, y: origin.y, width: size.width * scale, height: size.height * scale)
    }

    /// Renders strokes into a bitmap the size of the view, so a canvas only redraws the
    /// stroke in progress while the pen moves. Returns an upright image.
    static func cache(_ strokes: [InkStroke], drawingSize: CGSize, bounds: CGRect, pixelScale: Double) -> CGImage? {
        let width = Int((bounds.width * pixelScale).rounded()), height = Int((bounds.height * pixelScale).rounded())
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let viewport = InkViewport(drawingSize: drawingSize, in: CGRect(origin: .zero, size: bounds.size))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: pixelScale, y: -pixelScale)
        context.translateBy(x: viewport.origin.x, y: viewport.origin.y)
        context.scaleBy(x: viewport.scale, y: viewport.scale)
        for stroke in strokes { InkRenderer.draw(stroke, in: context) }
        return context.makeImage()
    }

    /// Draws a canvas frame in a top-left-origin context: paper, cached strokes, live stroke.
    static func drawFrame(in context: CGContext, bounds: CGRect, editor: InkEditor, cache: CGImage?, eraserAt hover: CGPoint?) {
        let drawing = editor.drawing
        let viewport = InkViewport(drawingSize: drawing.size, in: bounds)
        let paper = viewport.paperRect(for: drawing.size)
        context.setFillColor((drawing.background ?? .paper).cgColor())
        context.fill(paper)
        if let cache {
            // CGImages draw bottom-up; flip once so the cache lands upright.
            context.saveGState()
            context.translateBy(x: 0, y: bounds.height)
            context.scaleBy(x: 1, y: -1)
            context.draw(cache, in: CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height))
            context.restoreGState()
        }
        context.saveGState()
        context.clip(to: paper)
        context.translateBy(x: viewport.origin.x, y: viewport.origin.y)
        context.scaleBy(x: viewport.scale, y: viewport.scale)
        if var live = editor.live {
            live.points += editor.prediction
            InkRenderer.draw(live, in: context)
        }
        if editor.tool == .eraser, let hover {
            let r = InkTool.eraser.width(size: editor.size, pressure: 1) / 2
            let point = viewport.toDrawing(hover)
            context.setStrokeColor(CGColor(gray: 0.3, alpha: 0.6))
            context.setLineWidth(1 / viewport.scale)
            context.strokeEllipse(in: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2))
        }
        context.restoreGState()
    }
}
