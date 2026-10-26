import SwiftUI

/// A slowly drifting mesh of the theme's glow colors behind the page.
struct AmbientBackground: View {
    let theme: Theme
    let animated: Bool

    var body: some View {
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 6)) { context in
                mesh(time: context.date.timeIntervalSinceReferenceDate)
            }
        } else {
            mesh(time: 0)
        }
    }

    private func mesh(time t: Double) -> some View {
        let s = Float(t)
        func wobble(_ phase: Float, _ amount: Float = 0.06) -> Float { sin(s * 0.13 + phase) * amount }
        let points: [SIMD2<Float>] = [
            [0, 0], [0.5 + wobble(1), 0], [1, 0],
            [0, 0.5 + wobble(2)], [0.5 + wobble(3, 0.12), 0.5 + wobble(4, 0.12)], [1, 0.5 + wobble(5)],
            [0, 1], [0.5 + wobble(6), 1], [1, 1],
        ]
        let bg = theme.bg
        let g = theme.glow.map { Color(nsColor: $0) }
        return MeshGradient(width: 3, height: 3, points: points, colors: [
            g[0], bg, g[2],
            bg, bg, bg,
            g[2], g[1], g[0],
        ])
        .overlay(theme.bg.opacity(0.35))
        .ignoresSafeArea()
    }
}

/// A circular progress ring that fills toward a goal and glows when complete.
struct GoalRing: View {
    let progress: Double
    var lineWidth: CGFloat = 3
    var tint: Color = .accentColor

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress >= 1 {
                Image(systemName: "checkmark")
                    .font(.system(size: lineWidth * 2.4, weight: .heavy))
                    .foregroundStyle(tint)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.6, bounce: 0.3), value: progress)
    }
}

/// The momentum flame: grows and warms up the longer you keep writing.
struct MomentumFlame: View {
    let level: Int

    var body: some View {
        Image(systemName: level == 0 ? "flame" : "flame.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(gradient)
            .scaleEffect(1 + CGFloat(level) * 0.14)
            .symbolEffect(.breathe, isActive: level >= 2)
            .animation(.spring(duration: 0.5, bounce: 0.5), value: level)
            .help(["Start typing to build momentum", "Warming up", "In the flow", "On fire!"][level])
    }

    private var gradient: AnyShapeStyle {
        switch level {
        case 0: AnyShapeStyle(.secondary)
        case 1: AnyShapeStyle(LinearGradient(colors: [.orange.opacity(0.7), .yellow.opacity(0.7)], startPoint: .bottom, endPoint: .top))
        case 2: AnyShapeStyle(LinearGradient(colors: [.red, .orange, .yellow], startPoint: .bottom, endPoint: .top))
        default: AnyShapeStyle(LinearGradient(colors: [.pink, .red, .orange, .yellow], startPoint: .bottom, endPoint: .top))
        }
    }
}

/// Physics-lite confetti drawn in a single Canvas.
struct ConfettiView: View {
    private struct Piece {
        let x: Double, delay: Double, vx: Double, vy: Double, spin: Double, size: Double, hue: Color, isCircle: Bool
    }

    private let pieces: [Piece]
    private let start = Date.now

    init(count: Int = 140, colors: [Color] = [.pink, .orange, .yellow, .mint, .cyan, .purple, .red]) {
        pieces = (0..<count).map { _ in
            Piece(x: .random(in: 0...1), delay: .random(in: 0...0.5), vx: .random(in: -80...80), vy: .random(in: -520 ... -220),
                  spin: .random(in: -8...8), size: .random(in: 6...11), hue: colors.randomElement()!, isCircle: .random())
        }
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                for p in pieces {
                    let time = t - p.delay
                    guard time > 0 else { continue }
                    let x = p.x * size.width + p.vx * time
                    let y = size.height * 0.15 + p.vy * time + 0.5 * 700 * time * time
                    guard y < size.height + 20 else { continue }
                    let opacity = max(0, min(1, 3.6 - time))
                    var piece = context
                    piece.opacity = opacity
                    piece.translateBy(x: x, y: y)
                    piece.rotate(by: .radians(p.spin * time))
                    piece.scaleBy(x: 1, y: abs(cos(p.spin * time * 0.7)) * 0.8 + 0.2)
                    let rect = CGRect(x: -p.size / 2, y: -p.size / 3, width: p.size, height: p.size * 0.66)
                    piece.fill(p.isCircle ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 1.5), with: .color(p.hue))
                }
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

struct CelebrationCard: View {
    let celebration: Celebration

    var body: some View {
        VStack(spacing: 6) {
            Text(celebration.emoji).font(.system(size: 46))
            Text(celebration.title).font(.title2.weight(.bold))
            Text(celebration.subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
        .frame(maxWidth: 360)
        .themedGlass(in: .rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.12), radius: 30, y: 10)
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        Label(toast.message, systemImage: toast.symbol)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .themedGlass(in: .capsule)
    }
}

extension TimeInterval {
    var readableMinutes: String {
        let minutes = Int((self / 60).rounded())
        if minutes < 1 { return "< 1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}
