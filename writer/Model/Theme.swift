import AppKit
import SwiftUI

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

/// The living scene drawn behind the page.
enum Atmosphere: String {
    case ink, stars, dust, leaves, fireflies, waves, petals, mist, matrix
    /// A plain page: no scene at all.
    case none

    /// The slowest redraw rate that still looks smooth for this scene; 0 means fully static.
    var framesPerSecond: Double {
        switch self {
        case .petals, .leaves, .fireflies: 20
        case .matrix, .waves, .dust: 15
        case .stars: 10
        case .mist: 8
        case .ink, .none: 0
        }
    }
}

/// An atmosphere: not just editor colors, but a whole place to write in. It colors the
/// page, the panels around it, the garden, and the scene that drifts behind everything.
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let tagline: String
    let isDark: Bool
    let background: NSColor
    let text: NSColor
    let muted: NSColor
    let accent: NSColor
    let heading: NSColor
    let codeBackground: NSColor
    /// Soft colors blended into the backdrop gradient.
    let glow: [NSColor]
    /// The tint of the sidebar and sheet list panels.
    let panel: NSColor
    /// Leaves and stems in the Writing Garden.
    let leaf: NSColor
    /// Colors of the drifting particles (petals, stars, fireflies…).
    let particles: [NSColor]
    let atmosphere: Atmosphere
    /// A typeface the atmosphere insists on (Terminal is monospaced); nil keeps your choice.
    var font: EditorFontChoice? = nil

    var bg: Color { Color(nsColor: background) }
    var fg: Color { Color(nsColor: text) }
    var mutedColor: Color { Color(nsColor: muted) }
    var accentColor: Color { Color(nsColor: accent) }
    var panelColor: Color { Color(nsColor: panel) }
    var leafColor: Color { Color(nsColor: leaf) }
    var colorScheme: ColorScheme { isDark ? .dark : .light }

    static let all: [Theme] = [
        Theme(id: "white", name: "Plain White", tagline: "Just a white page", isDark: false,
              background: NSColor(hex: 0xFFFFFF), text: NSColor(hex: 0x1D1D1F), muted: NSColor(hex: 0xA1A1A6),
              accent: NSColor(hex: 0x0A84FF), heading: NSColor(hex: 0x000000), codeBackground: NSColor(hex: 0xF2F2F4),
              glow: [NSColor(hex: 0xFFFFFF), NSColor(hex: 0xFFFFFF), NSColor(hex: 0xFFFFFF)],
              panel: NSColor(hex: 0xF5F5F7), leaf: NSColor(hex: 0x34C759),
              particles: [NSColor(hex: 0x000000)], atmosphere: .none),
        Theme(id: "black", name: "Plain Black", tagline: "Just a black page", isDark: true,
              background: NSColor(hex: 0x000000), text: NSColor(hex: 0xE5E5E7), muted: NSColor(hex: 0x636366),
              accent: NSColor(hex: 0x0A84FF), heading: NSColor(hex: 0xFFFFFF), codeBackground: NSColor(hex: 0x1C1C1E),
              glow: [NSColor(hex: 0x000000), NSColor(hex: 0x000000), NSColor(hex: 0x000000)],
              panel: NSColor(hex: 0x111113), leaf: NSColor(hex: 0x30D158),
              particles: [NSColor(hex: 0xFFFFFF)], atmosphere: .none),
        Theme(id: "paper", name: "Washi", tagline: "Rice paper and drifting ink", isDark: false,
              background: NSColor(hex: 0xFBF8F3), text: NSColor(hex: 0x2B2A28), muted: NSColor(hex: 0xADA69C),
              accent: NSColor(hex: 0xD9480F), heading: NSColor(hex: 0x1C1B19), codeBackground: NSColor(hex: 0xF1EBE2),
              glow: [NSColor(hex: 0xF6E7D6), NSColor(hex: 0xFBF4EA), NSColor(hex: 0xEDEFF5)],
              panel: NSColor(hex: 0xF2ECE2), leaf: NSColor(hex: 0x6E8F55),
              particles: [NSColor(hex: 0x2B2A28)], atmosphere: .ink),
        Theme(id: "midnight", name: "Starlight", tagline: "A quiet sky full of stars", isDark: true,
              background: NSColor(hex: 0x0F1220), text: NSColor(hex: 0xDADDE6), muted: NSColor(hex: 0x5D6478),
              accent: NSColor(hex: 0x8FB4FF), heading: NSColor(hex: 0xF4F6FB), codeBackground: NSColor(hex: 0x1A1F33),
              glow: [NSColor(hex: 0x1C2547), NSColor(hex: 0x241B3D), NSColor(hex: 0x0E2230)],
              panel: NSColor(hex: 0x141A2E), leaf: NSColor(hex: 0x7FB5A0),
              particles: [NSColor(hex: 0xFFFFFF), NSColor(hex: 0xCFE0FF), NSColor(hex: 0xFFE9B8)], atmosphere: .stars),
        Theme(id: "terminal", name: "Terminal", tagline: "Phosphor green and digital rain", isDark: true,
              background: NSColor(hex: 0x070B08), text: NSColor(hex: 0xB9F5C4), muted: NSColor(hex: 0x3F6B4A),
              accent: NSColor(hex: 0x39FF88), heading: NSColor(hex: 0xDCFFE4), codeBackground: NSColor(hex: 0x0F1D14),
              glow: [NSColor(hex: 0x0B2414), NSColor(hex: 0x07120B), NSColor(hex: 0x0D1F18)],
              panel: NSColor(hex: 0x0B120D), leaf: NSColor(hex: 0x39FF88),
              particles: [NSColor(hex: 0x39FF88), NSColor(hex: 0x2BD46F), NSColor(hex: 0xA4FFC4)], atmosphere: .matrix,
              font: .mono),
        Theme(id: "forest", name: "Bamboo", tagline: "A green grove, leaves drifting down", isDark: true,
              background: NSColor(hex: 0x101C16), text: NSColor(hex: 0xD6E3D8), muted: NSColor(hex: 0x5C7867),
              accent: NSColor(hex: 0x8FD694), heading: NSColor(hex: 0xEFF7F0), codeBackground: NSColor(hex: 0x182A20),
              glow: [NSColor(hex: 0x173A28), NSColor(hex: 0x122A2A), NSColor(hex: 0x223321)],
              panel: NSColor(hex: 0x14241B), leaf: NSColor(hex: 0x8FD694),
              particles: [NSColor(hex: 0x86C46D), NSColor(hex: 0xC9C46A), NSColor(hex: 0x5FA05A)], atmosphere: .leaves),
        Theme(id: "dusk", name: "Fireflies", tagline: "Violet dusk and wandering lights", isDark: true,
              background: NSColor(hex: 0x1A1626), text: NSColor(hex: 0xE6DFF5), muted: NSColor(hex: 0x6E648A),
              accent: NSColor(hex: 0xFFB86B), heading: NSColor(hex: 0xFFFFFF), codeBackground: NSColor(hex: 0x262036),
              glow: [NSColor(hex: 0x37204A), NSColor(hex: 0x1F2142), NSColor(hex: 0x3A2436)],
              panel: NSColor(hex: 0x201B2F), leaf: NSColor(hex: 0x9BC48A),
              particles: [NSColor(hex: 0xF7E68A), NSColor(hex: 0xD4F28A)], atmosphere: .fireflies),
        Theme(id: "ocean", name: "Tide", tagline: "Sea glass and slow waves", isDark: false,
              background: NSColor(hex: 0xEEF5F7), text: NSColor(hex: 0x1D3340), muted: NSColor(hex: 0x8BA5B2),
              accent: NSColor(hex: 0x0A84A8), heading: NSColor(hex: 0x0F2430), codeBackground: NSColor(hex: 0xE0ECF1),
              glow: [NSColor(hex: 0xCDEAF3), NSColor(hex: 0xE4F4EE), NSColor(hex: 0xDCE5F8)],
              panel: NSColor(hex: 0xE2EDF1), leaf: NSColor(hex: 0x4E9A84),
              particles: [NSColor(hex: 0x3BA7C6), NSColor(hex: 0x7CCBE0), NSColor(hex: 0x0A84A8)], atmosphere: .waves),
        Theme(id: "rose", name: "Sakura", tagline: "Blossoms tumbling on the breeze", isDark: false,
              background: NSColor(hex: 0xFFF6F5), text: NSColor(hex: 0x4A2C33), muted: NSColor(hex: 0xC59CA5),
              accent: NSColor(hex: 0xD6336C), heading: NSColor(hex: 0x3A1D24), codeBackground: NSColor(hex: 0xFBE6E8),
              glow: [NSColor(hex: 0xFFDCE4), NSColor(hex: 0xFFF0E6), NSColor(hex: 0xF3E3FF)],
              panel: NSColor(hex: 0xFBEAEB), leaf: NSColor(hex: 0x7FA36B),
              particles: [NSColor(hex: 0xFFB7C5), NSColor(hex: 0xFFD1DC), NSColor(hex: 0xF69AB0)], atmosphere: .petals),
        Theme(id: "stone", name: "Stone Garden", tagline: "Raked sand, moss and morning mist", isDark: false,
              background: NSColor(hex: 0xEFEDE8), text: NSColor(hex: 0x33312D), muted: NSColor(hex: 0xA19D94),
              accent: NSColor(hex: 0x5F7A4F), heading: NSColor(hex: 0x24231F), codeBackground: NSColor(hex: 0xE4E1DA),
              glow: [NSColor(hex: 0xE2E5DC), NSColor(hex: 0xF3F1EC), NSColor(hex: 0xE6E2DA)],
              panel: NSColor(hex: 0xE6E3DC), leaf: NSColor(hex: 0x6F8B5A),
              particles: [NSColor(hex: 0xFFFFFF)], atmosphere: .mist),
    ]

    static func named(_ id: String) -> Theme {
        // Candlelight was retired in favor of Terminal.
        let id = id == "sepia" ? "terminal" : id
        return all.first { $0.id == id } ?? all[0]
    }
}
