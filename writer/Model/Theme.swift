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

/// The scene drawn behind the page. Most themes are a plain page; a few keep a quiet scene.
enum Atmosphere: String {
    case ink, stars, matrix
    /// A plain page: no scene at all.
    case none

    /// The slowest redraw rate that still looks smooth for this scene; 0 means fully static.
    var framesPerSecond: Double {
        switch self {
        case .matrix: 15
        case .stars: 10
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

    /// The page the words sit on. Dark themes lift it a touch off the desk.
    var paperColor: Color {
        isDark ? Color(nsColor: background.blended(withFraction: 0.035, of: .white) ?? background) : bg
    }
    /// The desk under the page: a shade deeper than the paper, in the paper's own hue.
    var deskColor: Color {
        isDark ? bg : Color(nsColor: background.blended(withFraction: 0.07, of: text) ?? background)
    }

    // Four light, four dark. Plain pages first: the words are the point.
    static let all: [Theme] = [
        Theme(id: "paper", name: "Paper", tagline: "Warm off-white, soft ink", isDark: false,
              background: NSColor(hex: 0xFBF9F5), text: NSColor(hex: 0x2B2926), muted: NSColor(hex: 0xA8A29A),
              accent: NSColor(hex: 0xC05A30), heading: NSColor(hex: 0x1A1917), codeBackground: NSColor(hex: 0xF2EEE7),
              glow: [NSColor(hex: 0xFBF9F5), NSColor(hex: 0xFBF9F5), NSColor(hex: 0xFBF9F5)],
              panel: NSColor(hex: 0xF3F0EA), leaf: NSColor(hex: 0x6E8F55),
              particles: [NSColor(hex: 0x2B2926)], atmosphere: .none),
        Theme(id: "white", name: "White", tagline: "Crisp and neutral", isDark: false,
              background: NSColor(hex: 0xFFFFFF), text: NSColor(hex: 0x1F1F21), muted: NSColor(hex: 0xA1A1A6),
              accent: NSColor(hex: 0x2F6FEB), heading: NSColor(hex: 0x000000), codeBackground: NSColor(hex: 0xF3F3F5),
              glow: [NSColor(hex: 0xFFFFFF), NSColor(hex: 0xFFFFFF), NSColor(hex: 0xFFFFFF)],
              panel: NSColor(hex: 0xF6F6F8), leaf: NSColor(hex: 0x34C759),
              particles: [NSColor(hex: 0x1F1F21)], atmosphere: .none),
        Theme(id: "parchment", name: "Sepia", tagline: "Easy on the eyes for long sessions", isDark: false,
              background: NSColor(hex: 0xF4ECDF), text: NSColor(hex: 0x3F3326), muted: NSColor(hex: 0xA8987F),
              accent: NSColor(hex: 0xA4532B), heading: NSColor(hex: 0x2C2218), codeBackground: NSColor(hex: 0xEAE0CF),
              glow: [NSColor(hex: 0xF4ECDF), NSColor(hex: 0xF4ECDF), NSColor(hex: 0xF4ECDF)],
              panel: NSColor(hex: 0xECE2D2), leaf: NSColor(hex: 0x7A8B4E),
              particles: [NSColor(hex: 0x3F3326)], atmosphere: .none),
        Theme(id: "washi", name: "Ink Wash", tagline: "Rice paper and distant mountains", isDark: false,
              background: NSColor(hex: 0xFBF8F3), text: NSColor(hex: 0x2B2A28), muted: NSColor(hex: 0xADA69C),
              accent: NSColor(hex: 0xC4502A), heading: NSColor(hex: 0x1C1B19), codeBackground: NSColor(hex: 0xF1EBE2),
              glow: [NSColor(hex: 0xF6E9DA), NSColor(hex: 0xFBF5EC), NSColor(hex: 0xEEF0F4)],
              panel: NSColor(hex: 0xF2ECE2), leaf: NSColor(hex: 0x6E8F55),
              particles: [NSColor(hex: 0x2B2A28)], atmosphere: .ink),
        Theme(id: "graphite", name: "Graphite", tagline: "A soft dark gray", isDark: true,
              background: NSColor(hex: 0x1E1F22), text: NSColor(hex: 0xD9D9DC), muted: NSColor(hex: 0x6B6D73),
              accent: NSColor(hex: 0x7FA7F5), heading: NSColor(hex: 0xF2F2F4), codeBackground: NSColor(hex: 0x2A2B2F),
              glow: [NSColor(hex: 0x1E1F22), NSColor(hex: 0x1E1F22), NSColor(hex: 0x1E1F22)],
              panel: NSColor(hex: 0x18191B), leaf: NSColor(hex: 0x7FC08A),
              particles: [NSColor(hex: 0xD9D9DC)], atmosphere: .none),
        Theme(id: "black", name: "Black", tagline: "True black, for night owls", isDark: true,
              background: NSColor(hex: 0x050505), text: NSColor(hex: 0xE3E3E5), muted: NSColor(hex: 0x5E5E63),
              accent: NSColor(hex: 0x4D9BFF), heading: NSColor(hex: 0xFFFFFF), codeBackground: NSColor(hex: 0x17171A),
              glow: [NSColor(hex: 0x050505), NSColor(hex: 0x050505), NSColor(hex: 0x050505)],
              panel: NSColor(hex: 0x0F0F11), leaf: NSColor(hex: 0x30D158),
              particles: [NSColor(hex: 0xFFFFFF)], atmosphere: .none),
        Theme(id: "midnight", name: "Starlight", tagline: "Deep navy under a quiet sky", isDark: true,
              background: NSColor(hex: 0x0F1220), text: NSColor(hex: 0xDADDE6), muted: NSColor(hex: 0x5D6478),
              accent: NSColor(hex: 0x8FB4FF), heading: NSColor(hex: 0xF4F6FB), codeBackground: NSColor(hex: 0x1A1F33),
              glow: [NSColor(hex: 0x1A2240), NSColor(hex: 0x1E1A36), NSColor(hex: 0x0E1F2C)],
              panel: NSColor(hex: 0x131828), leaf: NSColor(hex: 0x7FB5A0),
              particles: [NSColor(hex: 0xFFFFFF), NSColor(hex: 0xCFE0FF), NSColor(hex: 0xFFE9B8)], atmosphere: .stars),
        Theme(id: "terminal", name: "Terminal", tagline: "Phosphor green on black", isDark: true,
              background: NSColor(hex: 0x070B08), text: NSColor(hex: 0xB9F5C4), muted: NSColor(hex: 0x3F6B4A),
              accent: NSColor(hex: 0x39FF88), heading: NSColor(hex: 0xDCFFE4), codeBackground: NSColor(hex: 0x0F1D14),
              glow: [NSColor(hex: 0x0B2414), NSColor(hex: 0x07120B), NSColor(hex: 0x0D1F18)],
              panel: NSColor(hex: 0x0B120D), leaf: NSColor(hex: 0x39FF88),
              particles: [NSColor(hex: 0x39FF88), NSColor(hex: 0x2BD46F), NSColor(hex: 0xA4FFC4)], atmosphere: .matrix,
              font: .mono),
    ]

    /// Retired themes, and where their writers land now.
    private static let retired = [
        "sepia": "terminal", // Candlelight became Terminal
        "stone": "paper", "rose": "paper", "ocean": "white", "forest": "graphite", "dusk": "midnight",
    ]

    static func named(_ id: String) -> Theme {
        let id = retired[id] ?? id
        return all.first { $0.id == id } ?? all[0]
    }
}
