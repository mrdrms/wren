import SwiftUI

extension EnvironmentValues {
    /// The window's full frame (global coordinates), so every panel can draw its slice of one
    /// continuous scene instead of each drawing its own.
    @Entry var sceneFrame: CGRect = .zero
}

/// The scene behind everything: a soft gradient plus, for a few themes, a quiet layer of
/// stars, ink or digital rain. Every particle is a pure function of time,
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
                // Never leave part of this view unpainted, even if the window measurement lags.
                let whole = sceneFrame.union(frame)
                scene
                    .frame(width: whole.width, height: whole.height)
                    .offset(x: whole.minX - frame.minX, y: whole.minY - frame.minY)
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
        case (.ink, .back):
            ink(&g)
            inkSun(&g)
            hills(&g, color: color(0), alphas: [0.06, 0.1, 0.15])
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

}
