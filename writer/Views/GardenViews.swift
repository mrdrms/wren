import SwiftUI

/// Hand-drawn plants for the Writing Garden. Level 0 is a resting pebble; 1–3 grow from
/// sprout to bud; 4 is a full bloom (the daily goal met).
enum GardenArt {
    static func level(words: Int, goal: Int) -> Int {
        guard words > 0 else { return 0 }
        let ratio = Double(words) / Double(max(1, goal))
        switch ratio {
        case ..<0.34: return 1
        case ..<0.67: return 2
        case ..<1: return 3
        default: return 4
        }
    }

    static let labels = ["Resting", "Sprout", "Growing", "Budding", "In bloom"]

    /// Draws a plant whose base sits at `base`. `size` is roughly the height of a full bloom.
    static func drawPlant(_ g: inout GraphicsContext, at base: CGPoint, level: Int, size: CGFloat, theme: Theme, seed: Int, sway: Double) {
        let leaf = Color(nsColor: theme.leaf)
        let accent = Color(nsColor: theme.accent)
        func rand(_ k: Int) -> CGFloat {
            let x = sin(Double(seed) * 12.9898 + Double(k) * 78.233) * 43_758.5453
            return CGFloat(x - floor(x))
        }

        if level == 0 {
            // Rest days are quiet sand; only now and then a stone.
            guard rand(11) > 0.72 || seed == 7 else { return }
            let w = size * (0.2 + rand(1) * 0.14), h = w * 0.55
            g.fill(Path(ellipseIn: CGRect(x: base.x - w / 2, y: base.y - h, width: w, height: h)),
                   with: .color(Color(nsColor: theme.muted).opacity(0.22)))
            return
        }

        let heights: [CGFloat] = [0, 0.32, 0.52, 0.68, 0.78]
        let height = size * heights[level] * (0.9 + rand(2) * 0.2)
        let lean = CGFloat(sin(sway + Double(seed))) * size * 0.04 + (rand(3) - 0.5) * size * 0.08
        let top = CGPoint(x: base.x + lean, y: base.y - height)

        var stem = Path()
        stem.move(to: base)
        stem.addQuadCurve(to: top, control: CGPoint(x: base.x + lean * 0.2 + (rand(4) - 0.5) * size * 0.1, y: base.y - height * 0.55))
        g.stroke(stem, with: .color(leaf.opacity(0.9)), style: StrokeStyle(lineWidth: max(1, size * 0.035), lineCap: .round))

        func drawLeaf(at t: CGFloat, side: CGFloat, length: CGFloat) {
            let point = CGPoint(x: base.x + (top.x - base.x) * t, y: base.y + (top.y - base.y) * t)
            var leafContext = g
            leafContext.translateBy(x: point.x, y: point.y)
            leafContext.rotate(by: .radians(Double(side) * (0.9 + Double(rand(Int(t * 10) + 5)) * 0.4) - .pi / 2 + sway * 0.05))
            var path = Path()
            path.move(to: .zero)
            path.addQuadCurve(to: CGPoint(x: length, y: 0), control: CGPoint(x: length * 0.5, y: -length * 0.42))
            path.addQuadCurve(to: .zero, control: CGPoint(x: length * 0.5, y: length * 0.42))
            leafContext.fill(path, with: .color(leaf.opacity(0.85)))
        }

        let leafSize = size * 0.17
        drawLeaf(at: 0.92, side: -1, length: leafSize * 0.8)
        drawLeaf(at: 0.92, side: 1, length: leafSize * 0.8)
        if level >= 2 {
            drawLeaf(at: 0.45, side: -1, length: leafSize)
            drawLeaf(at: 0.6, side: 1, length: leafSize)
        }

        if level == 3 {
            let bud = size * 0.09
            g.fill(Path(ellipseIn: CGRect(x: top.x - bud * 0.7, y: top.y - bud * 1.6, width: bud * 1.4, height: bud * 1.9)),
                   with: .color(accent.opacity(0.85)))
        } else if level == 4 {
            let petal = size * 0.12
            for k in 0..<5 {
                var petalContext = g
                petalContext.translateBy(x: top.x, y: top.y - petal * 0.4)
                petalContext.rotate(by: .radians(Double(k) / 5 * .pi * 2 + Double(rand(9)) + sway * 0.02))
                petalContext.fill(Path(ellipseIn: CGRect(x: -petal * 0.45, y: -petal * 1.25, width: petal * 0.9, height: petal * 1.25)),
                                  with: .color(accent.opacity(0.88)))
            }
            let center = petal * 0.42
            g.fill(Path(ellipseIn: CGRect(x: top.x - center, y: top.y - petal * 0.4 - center, width: center * 2, height: center * 2)),
                   with: .color(Color(red: 1, green: 0.84, blue: 0.4)))
        }
    }
}

/// The Writing Garden: every day of the last few months, grown from the words you wrote.
struct GardenView: View {
    let log: WritingLog
    let goal: Int
    let theme: Theme
    var weeks = 26

    private struct Day {
        let date: Date
        let words: Int
        let column: Int
        let row: Int
    }

    private var days: [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let weekday = (calendar.component(.weekday, from: today) - calendar.firstWeekday + 7) % 7
        let first = calendar.date(byAdding: .day, value: -(weekday + (weeks - 1) * 7), to: today)!
        var result: [Day] = []
        for week in 0..<weeks {
            for day in 0..<7 {
                let date = calendar.date(byAdding: .day, value: week * 7 + day, to: first)!
                guard date <= today else { continue }
                result.append(Day(date: date, words: log.words(on: date), column: week, row: day))
            }
        }
        return result
    }

    var body: some View {
        let days = self.days
        GeometryReader { proxy in
            let cell = proxy.size.width / CGFloat(weeks)
            let rowHeight = proxy.size.height / 7
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1 / 12)) { timeline in
                    Canvas { g, size in
                        let sway = timeline.date.timeIntervalSinceReferenceDate * 0.8
                        drawSand(&g, size: size)
                        // Back rows first, so plants in front overlap the ones behind.
                        for day in days.sorted(by: { $0.row < $1.row }) {
                            let jitter = CGFloat(sin(Double(day.column * 7 + day.row) * 3.7)) * cell * 0.12
                            let base = CGPoint(x: (CGFloat(day.column) + 0.5) * cell + jitter, y: (CGFloat(day.row) + 0.92) * rowHeight)
                            if Calendar.current.isDateInToday(day.date) {
                                let glow = rowHeight * 0.9
                                g.fill(Path(ellipseIn: CGRect(x: base.x - glow, y: base.y - glow * 1.1, width: glow * 2, height: glow * 1.6)),
                                       with: .radialGradient(Gradient(colors: [Color(nsColor: theme.accent).opacity(0.22), .clear]),
                                                             center: CGPoint(x: base.x, y: base.y - glow * 0.3), startRadius: 0, endRadius: glow))
                            }
                            GardenArt.drawPlant(&g, at: base, level: GardenArt.level(words: day.words, goal: goal),
                                                size: min(cell * 1.6, rowHeight * 1.5), theme: theme, seed: day.column * 7 + day.row, sway: sway)
                        }
                    }
                }
                // Hover targets with each day's story.
                ForEach(days, id: \.date) { day in
                    Color.clear
                        .frame(width: cell, height: rowHeight)
                        .contentShape(.rect)
                        .help("\(day.date.formatted(date: .complete, time: .omitted))\n\(day.words == 0 ? "A rest day" : "\(day.words.formatted()) words · \(GardenArt.labels[GardenArt.level(words: day.words, goal: goal)].lowercased())")")
                        .offset(x: CGFloat(day.column) * cell, y: CGFloat(day.row) * rowHeight)
                }
            }
        }
    }

    /// Raked sand, the way a Zen garden is combed.
    private func drawSand(_ g: inout GraphicsContext, size: CGSize) {
        let lines = Int(size.height / 9)
        for i in 0..<lines {
            var path = Path()
            let y = CGFloat(i) * 9 + 4
            path.move(to: CGPoint(x: 0, y: y))
            for x in stride(from: 0, through: size.width, by: 12) {
                path.addLine(to: CGPoint(x: x, y: y + sin(x / 90 + CGFloat(i) * 0.15) * 2.2))
            }
            g.stroke(path, with: .color(Color(nsColor: theme.muted).opacity(0.13)), lineWidth: 0.8)
        }
    }
}

/// One plant, for legends and the sidebar card.
struct PlantView: View {
    let level: Int
    let theme: Theme
    var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !animated)) { timeline in
            Canvas { g, size in
                GardenArt.drawPlant(&g, at: CGPoint(x: size.width / 2, y: size.height * 0.96), level: level,
                                    size: size.height * 1.15, theme: theme, seed: 7,
                                    sway: timeline.date.timeIntervalSinceReferenceDate * 0.8)
            }
        }
    }
}
