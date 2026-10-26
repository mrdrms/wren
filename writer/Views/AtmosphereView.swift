import SwiftUI

extension EnvironmentValues {
    /// The window's full frame (global coordinates), so every panel can draw its slice of one
    /// continuous scene instead of each drawing its own.
    @Entry var sceneFrame: CGRect = .zero
}

/// The scene behind everything: a soft gradient plus a living layer of petals, stars,
/// fireflies, leaves, waves, dust, mist or ink. Every particle is a pure function of time,
/// so nothing is stored and the scene is identical however often it's redrawn.
struct AtmosphereView: View {
    let theme: Theme
    var animated = true
    /// Scales particle sizes for small previews.
    var scale: CGFloat = 1
    /// Draw this view's slice of the window-wide scene (for panels and the editor).
    var continuous = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.sceneFrame) private var sceneFrame

    var body: some View {
        if continuous && sceneFrame.width > 0 {
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                scene
                    .frame(width: sceneFrame.width, height: sceneFrame.height)
                    .offset(x: sceneFrame.minX - frame.minX, y: sceneFrame.minY - frame.minY)
            }
            .clipped()
            .allowsHitTesting(false)
        } else {
            scene
        }
    }

    private var scene: some View {
        let moving = animated && !reduceMotion && activeState != .inactive && !ProcessInfo.processInfo.isLowPowerModeEnabled
        let fps = theme.atmosphere.framesPerSecond
        return ZStack {
            if theme.atmosphere == .none {
                theme.bg
            } else {
                // The gradient's drift was too slow to see but cost ~6% CPU; keep it still.
                AmbientBackground(theme: theme, animated: false)
                // Scenery is drawn once; only the particles are redrawn, at the slowest rate
                // that still looks smooth for this scene.
                Canvas { context, size in
                    AtmosphereRenderer(theme: theme, size: size, t: 0, scale: scale).draw(&context, layer: .back)
                }
                if fps > 0 {
                    TimelineView(.animation(minimumInterval: 1 / fps, paused: !moving)) { timeline in
                        Canvas { context, size in
                            let t = moving ? timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000) : 1_000
                            AtmosphereRenderer(theme: theme, size: size, t: t, scale: scale).draw(&context, layer: .moving)
                        }
                    }
                }
                Canvas { context, size in
                    AtmosphereRenderer(theme: theme, size: size, t: 0, scale: scale).draw(&context, layer: .front)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct AtmosphereRenderer {
    let theme: Theme
    let size: CGSize
    let t: Double
    let scale: CGFloat

    private var W: Double { size.width }
    private var H: Double { size.height }

    /// Stable pseudo-random numbers in 0..<1.
    private func r(_ i: Int, _ k: Int) -> Double {
        let x = sin(Double(i) * 127.1 + Double(k) * 311.7) * 43_758.5453
        return x - floor(x)
    }

    private func color(_ i: Int) -> Color {
        Color(nsColor: theme.particles[i % theme.particles.count])
    }

    enum Layer { case back, moving, front }

    /// Static scenery goes in `back` and `front` (drawn once); particles go in `moving`.
    func draw(_ g: inout GraphicsContext, layer: Layer) {
        switch (theme.atmosphere, layer) {
        case (.stars, .back): moon(&g)
        case (.stars, .moving): stars(&g)
        case (.stars, .front): hills(&g, color: .black, alphas: [0.18, 0.3])
        case (.fireflies, .back): hills(&g, color: .black, alphas: [0.2, 0.32, 0.45])
        case (.fireflies, .moving): fireflies(&g)
        case (.petals, .back): branch(&g)
        case (.petals, .moving): falling(&g, count: 26, leaf: false)
        case (.leaves, .back): bamboo(&g)
        case (.leaves, .moving): falling(&g, count: 16, leaf: true)
        case (.dust, .moving): dust(&g)
        case (.waves, .moving): waves(&g)
        case (.ink, .back):
            ink(&g)
            inkSun(&g)
            hills(&g, color: color(0), alphas: [0.06, 0.1, 0.15])
        case (.mist, .back): stones(&g)
        case (.mist, .moving): mist(&g)
        case (.matrix, .moving): rain(&g)
        case (.matrix, .front): scanlines(&g)
        default: break
        }
    }

    // MARK: Terminal

    private static let glyphs = Array("01アイウエオカキクケコサシスセソタチツテト0123456789ABCDEF<>/{}$#=+;:")

    /// Digital rain: columns of glyphs falling, each led by a bright head.
    private func rain(_ g: inout GraphicsContext) {
        let spacing = 20 * Double(scale)
        let columns = Int(W / spacing) + 1
        let fontSize = 13 * scale
        // Resolve each glyph once per frame, then stamp it many times.
        let resolved = Self.glyphs.map { g.resolve(Text(String($0)).font(.system(size: fontSize, weight: .medium, design: .monospaced)).foregroundStyle(color(0))) }
        let heads = Self.glyphs.map { g.resolve(Text(String($0)).font(.system(size: fontSize, weight: .bold, design: .monospaced)).foregroundStyle(Color(nsColor: theme.heading))) }
        let trail = 14
        for column in 0..<columns where r(column, 1) > 0.45 {
            let speed = 0.05 + r(column, 2) * 0.09
            let fall = r(column, 3) + t * speed
            let headY = (fall - floor(fall)) * (H + Double(trail) * spacing) - spacing
            let x = Double(column) * spacing + spacing * 0.3
            for k in 0..<trail {
                let y = headY - Double(k) * spacing * 0.9
                guard y > -spacing, y < H + spacing else { continue }
                let index = Int(abs(sin(Double(column * 31 + k * 7) + floor(t * (2 + r(column, 4) * 4)) * 0.37)) * 10_000) % Self.glyphs.count
                var c = g
                c.opacity = k == 0 ? 0.75 : 0.42 * pow(1 - Double(k) / Double(trail), 1.5)
                c.draw(k == 0 ? heads[index] : resolved[index], at: CGPoint(x: x, y: y))
            }
        }
    }

    /// Faint CRT scanlines and a vignette.
    private func scanlines(_ g: inout GraphicsContext) {
        var y = 0.0
        while y < H {
            g.fill(Path(CGRect(x: 0, y: y, width: W, height: 1)), with: .color(.black.opacity(0.18)))
            y += 3
        }
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .radialGradient(Gradient(colors: [.clear, .black.opacity(0.45)]), center: CGPoint(x: W / 2, y: H / 2),
                                     startRadius: min(W, H) * 0.35, endRadius: max(W, H) * 0.75))
    }

    // MARK: Scenery

    /// Layered ridges along the bottom: ink-wash mountains, dark hills or a treeline.
    private func hills(_ g: inout GraphicsContext, color: Color, alphas: [Double]) {
        for (layer, alpha) in alphas.enumerated() {
            let base = H * (0.82 + Double(layer) * 0.06)
            let height = H * (0.16 - Double(layer) * 0.035)
            var path = Path()
            path.move(to: CGPoint(x: 0, y: H))
            for x in stride(from: 0.0, through: W + 8, by: 8) {
                let u = x / max(W, 1)
                let ridge = sin(u * 5.1 + Double(layer) * 1.7) * 0.45 + sin(u * 11.3 + Double(layer)) * 0.22 + sin(u * 23.7 + 2) * 0.08
                path.addLine(to: CGPoint(x: x, y: base - height * (0.55 + ridge)))
            }
            path.addLine(to: CGPoint(x: W, y: H))
            path.closeSubpath()
            g.fill(path, with: .linearGradient(Gradient(colors: [color.opacity(alpha), color.opacity(alpha * 0.55)]),
                                               startPoint: CGPoint(x: 0, y: base - height), endPoint: CGPoint(x: 0, y: H)))
        }
    }

    private func moon(_ g: inout GraphicsContext) {
        let radius = min(W, H) * 0.035
        let center = CGPoint(x: W * 0.84, y: H * 0.16)
        g.fill(Path(ellipseIn: CGRect(x: center.x - radius * 7, y: center.y - radius * 7, width: radius * 14, height: radius * 14)),
               with: .radialGradient(Gradient(colors: [Color.white.opacity(0.14), .clear]), center: center, startRadius: 0, endRadius: radius * 7))
        g.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
               with: .color(Color(red: 1, green: 0.97, blue: 0.9).opacity(0.9)))
    }

    private func inkSun(_ g: inout GraphicsContext) {
        let radius = min(W, H) * 0.07
        let center = CGPoint(x: W * 0.8, y: H * 0.24)
        g.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)),
               with: .color(Color(nsColor: theme.accent).opacity(0.16)))
    }

    /// Bamboo stalks framing the scene, swaying a little.
    private func bamboo(_ g: inout GraphicsContext) {
        let positions: [Double] = [0.015, 0.05, 0.085, 0.92, 0.955, 0.985]
        for (i, position) in positions.enumerated() {
            let width = max(4, W * (0.009 + r(i, 1) * 0.006))
            var stalk = g
            stalk.translateBy(x: position * W, y: H)
            stalk.rotate(by: .degrees(sin(t * 0.25 + Double(i)) * 0.8 + (position < 0.5 ? 1 : -1) * (1 + r(i, 2) * 2)))
            let segment = H * (0.11 + r(i, 3) * 0.04)
            let alpha = 0.16 + r(i, 4) * 0.1
            var y = 0.0
            while y > -H * 1.1 {
                let rect = CGRect(x: -width / 2, y: y - segment + 2, width: width, height: segment - 2)
                stalk.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .color(Color(nsColor: theme.leaf).opacity(alpha)))
                y -= segment
                if r(i, Int(-y)) > 0.6 { // leaves sprouting from a node
                    var leaf = Path()
                    let side: Double = r(i, Int(-y) + 1) > 0.5 ? 1 : -1
                    leaf.move(to: CGPoint(x: 0, y: y))
                    leaf.addQuadCurve(to: CGPoint(x: side * width * 5, y: y + width * 1.5), control: CGPoint(x: side * width * 2.5, y: y - width * 1.2))
                    leaf.addQuadCurve(to: CGPoint(x: 0, y: y), control: CGPoint(x: side * width * 2.5, y: y + width * 1.4))
                    stalk.fill(leaf, with: .color(Color(nsColor: theme.leaf).opacity(alpha * 1.3)))
                }
            }
        }
    }

    /// A cherry branch reaching in from the top corner, in blossom.
    private func branch(_ g: inout GraphicsContext) {
        let sway = sin(t * 0.3) * 2
        var path = Path()
        let start = CGPoint(x: W * 1.02, y: H * 0.02)
        let end = CGPoint(x: W * 0.7, y: H * 0.2 + sway)
        path.move(to: start)
        path.addCurve(to: end, control1: CGPoint(x: W * 0.92, y: H * 0.12), control2: CGPoint(x: W * 0.8, y: H * 0.1))
        g.stroke(path, with: .color(Color(red: 0.36, green: 0.24, blue: 0.24).opacity(0.38)), style: StrokeStyle(lineWidth: 5 * scale, lineCap: .round))
        var twig = Path()
        twig.move(to: CGPoint(x: W * 0.86, y: H * 0.11))
        twig.addQuadCurve(to: CGPoint(x: W * 0.8, y: H * 0.27 + sway), control: CGPoint(x: W * 0.85, y: H * 0.2))
        twig.move(to: CGPoint(x: W * 0.78, y: H * 0.15))
        twig.addQuadCurve(to: CGPoint(x: W * 0.72, y: H * 0.07), control: CGPoint(x: W * 0.74, y: H * 0.13))
        g.stroke(twig, with: .color(Color(red: 0.36, green: 0.24, blue: 0.24).opacity(0.32)), style: StrokeStyle(lineWidth: 2.5 * scale, lineCap: .round))
        // Blossom clusters along the branch.
        let spots: [(Double, Double)] = [(0.7, 0.2), (0.73, 0.17), (0.76, 0.13), (0.8, 0.27), (0.82, 0.22), (0.72, 0.07), (0.86, 0.1), (0.9, 0.07), (0.79, 0.11), (0.95, 0.05)]
        for (i, spot) in spots.enumerated() {
            let center = CGPoint(x: spot.0 * W, y: spot.1 * H + sway * (spot.1 * 4))
            let petal = (5 + r(i, 2) * 3) * scale
            for k in 0..<5 {
                var p = g
                p.translateBy(x: center.x, y: center.y)
                p.rotate(by: .radians(Double(k) / 5 * .pi * 2 + r(i, 3)))
                p.fill(Path(ellipseIn: CGRect(x: -petal * 0.5, y: -petal * 1.3, width: petal, height: petal * 1.3)), with: .color(color(i).opacity(0.75)))
            }
            g.fill(Path(ellipseIn: CGRect(x: center.x - petal * 0.35, y: center.y - petal * 0.35, width: petal * 0.7, height: petal * 0.7)),
                   with: .color(Color(nsColor: theme.accent).opacity(0.6)))
        }
    }

    /// Stones resting in raked sand, with ripples combed around them.
    private func stones(_ g: inout GraphicsContext) {
        let stones: [(x: Double, y: Double, r: Double)] = [(0.82, 0.86, 0.05), (0.9, 0.9, 0.028), (0.12, 0.92, 0.035)]
        for stone in stones {
            let center = CGPoint(x: stone.x * W, y: stone.y * H)
            let radius = stone.r * min(W, H) * 1.6
            for ring in 1...4 {
                let rr = radius * (1 + Double(ring) * 0.45)
                g.stroke(Path(ellipseIn: CGRect(x: center.x - rr, y: center.y - rr * 0.45, width: rr * 2, height: rr * 0.9)),
                         with: .color(Color(nsColor: theme.muted).opacity(0.16)), lineWidth: 1)
            }
            g.fill(Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius * 0.55, width: radius * 2, height: radius * 1.1)),
                   with: .linearGradient(Gradient(colors: [Color(nsColor: theme.muted).opacity(0.55), Color(nsColor: theme.text).opacity(0.35)]),
                                         startPoint: CGPoint(x: center.x, y: center.y - radius * 0.55), endPoint: CGPoint(x: center.x, y: center.y + radius * 0.55)))
        }
    }

    // MARK: Scenes

    private func stars(_ g: inout GraphicsContext) {
        let count = Int(min(140, max(30, W * H / 9_000)))
        for i in 0..<count {
            let x = r(i, 1) * W, y = r(i, 2) * H
            let twinkle = 0.25 + 0.75 * pow(abs(sin(t * (0.25 + r(i, 4) * 0.9) + r(i, 5) * 6.28)), 3)
            let s = (0.5 + r(i, 3) * 1.6) * scale
            g.fill(Path(ellipseIn: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2)), with: .color(color(i).opacity(twinkle * 0.85)))
            if r(i, 6) > 0.93 { // a few bright stars get a soft halo
                let halo = s * 5
                g.fill(Path(ellipseIn: CGRect(x: x - halo, y: y - halo, width: halo * 2, height: halo * 2)),
                       with: .radialGradient(Gradient(colors: [color(i).opacity(0.25 * twinkle), .clear]),
                                             center: CGPoint(x: x, y: y), startRadius: 0, endRadius: halo))
            }
        }
        // Now and then, a shooting star.
        let period = 14.0
        let phase = (t / period) - floor(t / period)
        if phase < 0.07 {
            let n = Int(floor(t / period))
            let p = phase / 0.07
            let start = CGPoint(x: (0.2 + r(n, 7) * 0.6) * W, y: r(n, 8) * H * 0.35)
            let head = CGPoint(x: start.x + 260 * p * scale, y: start.y + 110 * p * scale)
            let tail = CGPoint(x: head.x - 90 * scale, y: head.y - 38 * scale)
            var path = Path()
            path.move(to: tail)
            path.addLine(to: head)
            g.stroke(path, with: .linearGradient(Gradient(colors: [.clear, .white.opacity(0.9 * (1 - p))]), startPoint: tail, endPoint: head),
                     lineWidth: 1.4 * scale)
        }
    }

    private func fireflies(_ g: inout GraphicsContext) {
        for i in 0..<22 {
            let x = (r(i, 1) + sin(t * 0.07 * (1 + r(i, 3)) + r(i, 4) * 6.28) * 0.07) * W
            let y = (0.15 + r(i, 2) * 0.85 + cos(t * 0.06 * (1 + r(i, 5)) + r(i, 6) * 6.28) * 0.05) * H
            let pulse = max(0, sin(t * (0.6 + r(i, 7) * 0.8) + r(i, 8) * 6.28))
            let glow = pulse * pulse
            let radius = (10 + r(i, 9) * 10) * scale
            g.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(Gradient(colors: [color(i).opacity(0.55 * glow), .clear]), center: CGPoint(x: x, y: y),
                                         startRadius: 0, endRadius: radius))
            let core = 1.6 * scale
            g.fill(Path(ellipseIn: CGRect(x: x - core, y: y - core, width: core * 2, height: core * 2)), with: .color(color(i).opacity(0.3 + 0.7 * glow)))
        }
    }

    /// Petals or leaves drifting down, swaying and turning over as they fall.
    private func falling(_ g: inout GraphicsContext, count: Int, leaf: Bool) {
        for i in 0..<count {
            let speed = (leaf ? 0.012 : 0.018) + r(i, 3) * 0.02
            let fall = r(i, 2) + t * speed
            let progress = fall - floor(fall)
            let y = progress * (H + 80) - 40
            let x = r(i, 1) * W + sin(t * 0.5 * (0.5 + r(i, 4)) + r(i, 5) * 6.28) * 36 + progress * 70
            let spin = t * (0.6 + r(i, 6)) + r(i, 7) * 6.28
            let size = (leaf ? 13 : 9) * (0.7 + r(i, 8) * 0.6) * scale
            var piece = g
            piece.translateBy(x: x, y: y)
            piece.rotate(by: .radians(spin * 0.6))
            piece.scaleBy(x: max(0.15, abs(cos(spin))), y: 1)
            piece.opacity = 0.55 + r(i, 9) * 0.3
            var path = Path()
            if leaf {
                path.move(to: CGPoint(x: -size, y: 0))
                path.addQuadCurve(to: CGPoint(x: size, y: 0), control: CGPoint(x: 0, y: -size * 0.45))
                path.addQuadCurve(to: CGPoint(x: -size, y: 0), control: CGPoint(x: 0, y: size * 0.45))
            } else {
                // A petal with the little notch of a cherry blossom.
                path.move(to: CGPoint(x: 0, y: size * 0.9))
                path.addCurve(to: CGPoint(x: -size * 0.15, y: -size * 0.8), control1: CGPoint(x: -size * 0.9, y: size * 0.3), control2: CGPoint(x: -size * 0.7, y: -size * 0.7))
                path.addLine(to: CGPoint(x: 0, y: -size * 0.55))
                path.addLine(to: CGPoint(x: size * 0.15, y: -size * 0.8))
                path.addCurve(to: CGPoint(x: 0, y: size * 0.9), control1: CGPoint(x: size * 0.7, y: -size * 0.7), control2: CGPoint(x: size * 0.9, y: size * 0.3))
            }
            piece.fill(path, with: .color(color(i)))
        }
    }

    private func dust(_ g: inout GraphicsContext) {
        // A candle's warm glow, breathing.
        let flicker = 0.16 + 0.03 * sin(t * 2.3) + 0.02 * sin(t * 5.7 + 1)
        let center = CGPoint(x: W * 0.12, y: H * 0.95)
        g.fill(Path(CGRect(origin: .zero, size: size)),
               with: .radialGradient(Gradient(colors: [color(0).opacity(flicker), .clear]), center: center, startRadius: 0, endRadius: max(W, H) * 0.8))
        for i in 0..<70 {
            let rise = r(i, 2) + t * (0.004 + r(i, 3) * 0.008)
            let y = H - (rise - floor(rise)) * (H + 20)
            let x = r(i, 1) * W + sin(t * 0.3 * (0.5 + r(i, 4)) + r(i, 5) * 6.28) * 18
            let s = (0.6 + r(i, 6) * 1.6) * scale
            let alpha = 0.2 + 0.5 * abs(sin(t * (0.5 + r(i, 7)) + r(i, 8) * 6.28))
            g.fill(Path(ellipseIn: CGRect(x: x - s, y: y - s, width: s * 2, height: s * 2)), with: .color(color(i).opacity(alpha)))
        }
    }

    private func waves(_ g: inout GraphicsContext) {
        for layer in 0..<4 {
            let base = H * (0.80 + Double(layer) * 0.05)
            let amplitude = (8 + Double(layer) * 3) * Double(scale)
            let frequency = 1.4 + Double(layer) * 0.35
            let speed = 0.18 + Double(layer) * 0.07
            var path = Path()
            path.move(to: CGPoint(x: 0, y: H))
            for step in stride(from: 0.0, through: W, by: 8) {
                let y = base + sin(step / W * .pi * 2 * frequency + t * speed + Double(layer)) * amplitude
                    + sin(step / W * .pi * 2 * frequency * 2.3 - t * speed * 0.7) * amplitude * 0.35
                path.addLine(to: CGPoint(x: step, y: y))
            }
            path.addLine(to: CGPoint(x: W, y: H))
            path.closeSubpath()
            g.fill(path, with: .color(color(layer).opacity(0.07 + Double(layer) * 0.025)))
        }
        // Light glinting on the water.
        for i in 0..<18 {
            let x = r(i, 1) * W
            let y = H * (0.83 + r(i, 2) * 0.15)
            let shimmer = max(0, sin(t * (0.8 + r(i, 3)) + r(i, 4) * 6.28))
            g.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 10 * scale, height: 1.6 * scale)), with: .color(.white.opacity(0.5 * shimmer)))
        }
    }

    private func ink(_ g: inout GraphicsContext) {
        // Washes of ink, spreading and drifting very slowly.
        for i in 0..<5 {
            let x = (r(i, 1) + sin(t * 0.01 + Double(i)) * 0.06) * W
            let y = (r(i, 2) + cos(t * 0.008 + Double(i) * 2) * 0.05) * H
            let radius = (0.18 + r(i, 3) * 0.2) * max(W, H)
            g.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                   with: .radialGradient(Gradient(colors: [color(0).opacity(0.045), .clear]), center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius))
        }
        // Paper fibres.
        let fibres = Int(min(260, W * H / 4_000))
        for i in 0..<fibres {
            let x = r(i, 4) * W, y = r(i, 5) * H
            let length = (6 + r(i, 6) * 18) * Double(scale)
            let angle = r(i, 7) * .pi
            var path = Path()
            path.move(to: CGPoint(x: x, y: y))
            path.addQuadCurve(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                              control: CGPoint(x: x + cos(angle + 0.6) * length * 0.5, y: y + sin(angle + 0.6) * length * 0.5))
            g.stroke(path, with: .color(color(0).opacity(0.05)), lineWidth: 0.6)
        }
    }

    private func mist(_ g: inout GraphicsContext) {
        for i in 0..<6 {
            let drift = (r(i, 1) + t * (0.004 + r(i, 2) * 0.004))
            let x = (drift - floor(drift)) * (W * 1.6) - W * 0.3
            let y = (0.2 + r(i, 3) * 0.75) * H
            let width = (0.5 + r(i, 4) * 0.5) * W
            let height = (0.08 + r(i, 5) * 0.08) * H
            g.fill(Path(ellipseIn: CGRect(x: x - width / 2, y: y - height / 2, width: width, height: height)),
                   with: .radialGradient(Gradient(colors: [Color.white.opacity(0.45), .clear]), center: CGPoint(x: x, y: y),
                                         startRadius: 0, endRadius: width / 2))
        }
        // A few raked lines in the sand along the bottom.
        for line in 0..<5 {
            var path = Path()
            let base = H * (0.9 + Double(line) * 0.022)
            path.move(to: CGPoint(x: 0, y: base))
            for step in stride(from: 0.0, through: W, by: 10) {
                path.addLine(to: CGPoint(x: step, y: base + sin(step / 140 + Double(line) * 0.5) * 3))
            }
            g.stroke(path, with: .color(Color(nsColor: theme.muted).opacity(0.18)), lineWidth: 1)
        }
    }
}
