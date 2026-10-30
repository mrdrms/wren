import SwiftUI

// The only part of drawing that differs by device: turning pointer events into pen
// positions. Everything else (tools, smoothing, ink, eraser, undo) is in InkEditor.

#if os(macOS)
import AppKit

/// Mouse, trackpad and pen tablets. A tablet reports real pressure; anything else lets the
/// editor read pressure from speed.
final class InkCanvasView: NSView {
    let editor: InkEditor
    private var cache: CGImage?
    private var cacheKey: (size: CGSize, scale: Double)?
    private var hover: CGPoint?

    init(editor: InkEditor) {
        self.editor = editor
        super.init(frame: .zero)
        editor.onStrokesChanged = { [weak self] in self?.invalidateCache() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func invalidateCache() {
        cache = nil
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    private func point(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return InkViewport(drawingSize: editor.drawing.size, in: bounds).toDrawing(local)
    }

    private func pressure(_ event: NSEvent) -> Double? {
        event.subtype == .tabletPoint ? Double(event.pressure) : nil
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        editor.begin(at: point(event), pressure: pressure(event), time: event.timestamp)
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        hover = convert(event.locationInWindow, from: nil)
        editor.move(to: point(event), pressure: pressure(event), time: event.timestamp)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        editor.end()
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        hover = convert(event.locationInWindow, from: nil)
        if editor.tool == .eraser { needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hover = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let scale = Double(window?.backingScaleFactor ?? 2)
        if cache == nil || cacheKey?.size != bounds.size || cacheKey?.scale != scale {
            cache = InkViewport.cache(editor.drawing.strokes, drawingSize: editor.drawing.size, bounds: bounds, pixelScale: scale)
            cacheKey = (bounds.size, scale)
        }
        InkViewport.drawFrame(in: context, bounds: bounds, editor: editor, cache: cache, eraserAt: hover)
    }
}

struct InkCanvas: NSViewRepresentable {
    let editor: InkEditor

    func makeNSView(context: Context) -> InkCanvasView { InkCanvasView(editor: editor) }

    func updateNSView(_ view: InkCanvasView, context: Context) {
        // Tool changes redraw the eraser ring; stroke changes arrive through the editor.
        _ = editor.tool
        view.needsDisplay = true
    }
}

#else
import UIKit

/// Apple Pencil (with pressure, palm rejection and predicted touches) and fingers. Once a
/// Pencil has touched the canvas, fingers resting on the glass are ignored.
final class InkCanvasView: UIView {
    let editor: InkEditor
    private var cache: CGImage?
    private var cacheKey: (size: CGSize, scale: Double)?
    private var pencilSeen = false
    private weak var activeTouch: UITouch?

    init(editor: InkEditor) {
        self.editor = editor
        super.init(frame: .zero)
        isMultipleTouchEnabled = false
        backgroundColor = .clear
        editor.onStrokesChanged = { [weak self] in self?.invalidateCache() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func invalidateCache() {
        cache = nil
        setNeedsDisplay()
    }

    private func point(_ touch: UITouch) -> CGPoint {
        InkViewport(drawingSize: editor.drawing.size, in: bounds).toDrawing(touch.preciseLocation(in: self))
    }

    private func pressure(_ touch: UITouch) -> Double? {
        guard touch.type == .pencil, touch.maximumPossibleForce > 0 else { return nil }
        return Double(touch.force / touch.maximumPossibleForce)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        if touch.type == .pencil { pencilSeen = true }
        if pencilSeen && touch.type == .direct { return }
        activeTouch = touch
        editor.begin(at: point(touch), pressure: pressure(touch), time: touch.timestamp)
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        for sample in event?.coalescedTouches(for: touch) ?? [touch] {
            editor.move(to: point(sample), pressure: pressure(sample), time: sample.timestamp)
        }
        let predicted = (event?.predictedTouches(for: touch) ?? []).map(point)
        editor.move(to: point(touch), pressure: pressure(touch), time: touch.timestamp, predicted: predicted)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        editor.end()
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        editor.cancel()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        let scale = Double(window?.screen.scale ?? 2)
        if cache == nil || cacheKey?.size != bounds.size || cacheKey?.scale != scale {
            cache = InkViewport.cache(editor.drawing.strokes, drawingSize: editor.drawing.size, bounds: bounds, pixelScale: scale)
            cacheKey = (bounds.size, scale)
        }
        InkViewport.drawFrame(in: context, bounds: bounds, editor: editor, cache: cache, eraserAt: nil)
    }
}

struct InkCanvas: UIViewRepresentable {
    let editor: InkEditor

    func makeUIView(context: Context) -> InkCanvasView { InkCanvasView(editor: editor) }

    func updateUIView(_ view: InkCanvasView, context: Context) {
        _ = editor.tool
        view.setNeedsDisplay()
    }
}
#endif
