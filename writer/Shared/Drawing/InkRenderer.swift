import CoreGraphics
import Foundation
import ImageIO

/// Turns strokes into ink. Pure CoreGraphics, so a drawing looks identical on every device
/// and in every exported picture. Contexts are expected in drawing coordinates: origin at
/// the top left, y growing downward.
nonisolated enum InkRenderer {
    /// A point along the smoothed stroke and the width of the line there.
    struct Sample {
        var point: CGPoint
        var width: Double
    }

    static func draw(_ drawing: WrenDrawing, in context: CGContext, background: Bool = true) {
        if background, let paper = drawing.background {
            context.setFillColor(paper.cgColor())
            context.fill(CGRect(origin: .zero, size: drawing.size))
        }
        for stroke in drawing.strokes { draw(stroke, in: context) }
    }

    static func draw(_ stroke: InkStroke, in context: CGContext) {
        guard stroke.tool != .eraser else { return }
        let samples = smoothed(stroke)
        guard let first = samples.first else { return }
        context.saveGState()
        defer { context.restoreGState() }
        // One layer per stroke, so a see-through marker stays even where its segments overlap.
        context.setAlpha(stroke.tool.opacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        let color = stroke.color.cgColor()
        context.setFillColor(color)
        context.setStrokeColor(color)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if samples.count == 1 {
            let r = first.width / 2
            context.fillEllipse(in: CGRect(x: first.point.x - r, y: first.point.y - r, width: r * 2, height: r * 2))
        } else {
            for i in 1..<samples.count {
                let a = samples[i - 1], b = samples[i]
                context.setLineWidth((a.width + b.width) / 2)
                context.move(to: a.point)
                context.addLine(to: b.point)
                context.strokePath()
            }
        }
        context.endTransparencyLayer()
    }

    /// Catmull-Rom smoothing between the raw samples, with the width following pressure
    /// and, for the brush, tapering in and out the way a loaded brush does.
    static func smoothed(_ stroke: InkStroke) -> [Sample] {
        let points = stroke.points
        guard !points.isEmpty else { return [] }
        func width(_ p: InkPoint) -> Double { stroke.tool.width(size: stroke.size, pressure: p.pressure) }
        guard points.count > 1 else { return [Sample(point: points[0].cgPoint, width: width(points[0]))] }

        var samples: [Sample] = []
        samples.reserveCapacity(points.count * 4)
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            let gap = hypot(p2.x - p1.x, p2.y - p1.y)
            let steps = max(1, min(8, Int(gap / 2.5)))
            for s in 0..<steps {
                let t = Double(s) / Double(steps)
                let t2 = t * t, t3 = t2 * t
                func spline(_ a: Double, _ b: Double, _ c: Double, _ d: Double) -> Double {
                    0.5 * ((2 * b) + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                }
                let point = CGPoint(x: spline(p0.x, p1.x, p2.x, p3.x), y: spline(p0.y, p1.y, p2.y, p3.y))
                let w = width(p1) + (width(p2) - width(p1)) * t
                samples.append(Sample(point: point, width: w))
            }
        }
        samples.append(Sample(point: points[points.count - 1].cgPoint, width: width(points[points.count - 1])))

        if stroke.tool == .brush {
            // Distance from each end, so the tips thin to a point.
            var along = [0.0]
            for i in 1..<samples.count {
                along.append(along[i - 1] + hypot(samples[i].point.x - samples[i - 1].point.x, samples[i].point.y - samples[i - 1].point.y))
            }
            let total = along.last ?? 0
            let reach = max(6, stroke.size * 5)
            for i in samples.indices {
                let fromStart = min(1, along[i] / reach)
                let fromEnd = min(1, (total - along[i]) / (reach * 1.6))
                samples[i].width *= 0.25 + 0.75 * min(fromStart, fromEnd)
            }
        }
        return samples
    }

    /// The drawing as a PNG, `scale` pixels per canvas point.
    static func pngData(_ drawing: WrenDrawing, scale: Double = 2) -> Data? {
        let pixelWidth = Int((drawing.width * scale).rounded()), pixelHeight = Int((drawing.height * scale).rounded())
        guard pixelWidth > 0, pixelHeight > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        // Bitmap contexts start at the bottom left; flip to the drawing's top-left origin.
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        draw(drawing, in: context)
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}
