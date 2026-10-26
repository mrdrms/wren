import AppKit
import Foundation
import Observation

enum FocusLevel: String, CaseIterable, Identifiable {
    case off, sentence, paragraph

    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: "Off"
        case .sentence: "Sentence"
        case .paragraph: "Paragraph"
        }
    }
}

enum EditorFontChoice: String, CaseIterable, Identifiable {
    case serif, sans, rounded, mono

    var id: String { rawValue }
    var label: String {
        switch self {
        case .serif: "New York"
        case .sans: "SF Pro"
        case .rounded: "SF Rounded"
        case .mono: "SF Mono"
        }
    }
    var design: NSFontDescriptor.SystemDesign {
        switch self {
        case .serif: .serif
        case .sans: .default
        case .rounded: .rounded
        case .mono: .monospaced
        }
    }
}

/// User preferences, persisted to UserDefaults as they change.
@Observable
final class Preferences {
    static let shared = Preferences()

    @ObservationIgnored private let defaults = UserDefaults.standard

    var themeID: String { didSet { defaults.set(themeID, forKey: "themeID") } }
    var font: EditorFontChoice { didSet { defaults.set(font.rawValue, forKey: "font") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    var lineWidth: Double { didSet { defaults.set(lineWidth, forKey: "lineWidth") } }
    var lineHeight: Double { didSet { defaults.set(lineHeight, forKey: "lineHeight") } }
    var focus: FocusLevel { didSet { defaults.set(focus.rawValue, forKey: "focus") } }
    var typewriter: Bool { didSet { defaults.set(typewriter, forKey: "typewriter") } }
    var styleLens: Bool { didSet { defaults.set(styleLens, forKey: "styleLens") } }
    var keySounds: Bool { didSet { defaults.set(keySounds, forKey: "keySounds") } }
    var ambient: Bool { didSet { defaults.set(ambient, forKey: "ambient") } }
    var autoTitle: Bool { didSet { defaults.set(autoTitle, forKey: "autoTitle") } }
    var dailyGoal: Int { didSet { defaults.set(dailyGoal, forKey: "dailyGoal") } }
    var flowLock: Bool { didSet { defaults.set(flowLock, forKey: "flowLock") } }
    var rhythm: Bool { didSet { defaults.set(rhythm, forKey: "rhythm") } }
    var blogStyle: BlogStyle { didSet { defaults.set(blogStyle.rawValue, forKey: "blogStyle") } }
    var zenFullScreen: Bool { didSet { defaults.set(zenFullScreen, forKey: "zenFullScreen") } }
    /// Render Markdown in the editor (bigger headings, hidden marks…). Off: plain Markdown.
    var liveFormatting: Bool { didSet { defaults.set(liveFormatting, forKey: "liveFormatting") } }
    var hideMarkup: Bool { didSet { defaults.set(hideMarkup, forKey: "hideMarkup") } }
    var showFormatBar: Bool { didSet { defaults.set(showFormatBar, forKey: "showFormatBar") } }
    var pomodoroEnabled: Bool { didSet { defaults.set(pomodoroEnabled, forKey: "pomodoroEnabled") } }
    var pomodoroWork: Int { didSet { defaults.set(pomodoroWork, forKey: "pomodoroWork") } }
    var pomodoroShortBreak: Int { didSet { defaults.set(pomodoroShortBreak, forKey: "pomodoroShortBreak") } }
    var pomodoroLongBreak: Int { didSet { defaults.set(pomodoroLongBreak, forKey: "pomodoroLongBreak") } }
    var pomodoroLongEvery: Int { didSet { defaults.set(pomodoroLongEvery, forKey: "pomodoroLongEvery") } }
    var pomodoroAutoStart: Bool { didSet { defaults.set(pomodoroAutoStart, forKey: "pomodoroAutoStart") } }
    var pomodoroZen: Bool { didSet { defaults.set(pomodoroZen, forKey: "pomodoroZen") } }
    var pomodoroBreakScreen: Bool { didSet { defaults.set(pomodoroBreakScreen, forKey: "pomodoroBreakScreen") } }

    var theme: Theme { Theme.named(themeID) }

    private init() {
        defaults.register(defaults: [
            "themeID": "paper",
            "font": EditorFontChoice.serif.rawValue,
            "fontSize": 18.0,
            "lineWidth": 680.0,
            "lineHeight": 1.6,
            "focus": FocusLevel.off.rawValue,
            "typewriter": false,
            "styleLens": false,
            "keySounds": false,
            "ambient": true,
            "autoTitle": true,
            "dailyGoal": 500,
            "flowLock": false,
            "rhythm": false,
            "zenFullScreen": true,
            "liveFormatting": false,
            "hideMarkup": true,
            "showFormatBar": true,
            "pomodoroEnabled": false,
            "pomodoroWork": 25,
            "pomodoroShortBreak": 5,
            "pomodoroLongBreak": 15,
            "pomodoroLongEvery": 4,
            "pomodoroAutoStart": false,
            "pomodoroZen": false,
            "pomodoroBreakScreen": true,
        ])
        let savedTheme = defaults.string(forKey: "themeID") ?? "paper"
        themeID = savedTheme == "sepia" ? "terminal" : savedTheme // Candlelight became Terminal
        font = EditorFontChoice(rawValue: defaults.string(forKey: "font") ?? "") ?? .serif
        fontSize = defaults.double(forKey: "fontSize")
        lineWidth = defaults.double(forKey: "lineWidth")
        lineHeight = defaults.double(forKey: "lineHeight")
        focus = FocusLevel(rawValue: defaults.string(forKey: "focus") ?? "") ?? .off
        typewriter = defaults.bool(forKey: "typewriter")
        styleLens = defaults.bool(forKey: "styleLens")
        keySounds = defaults.bool(forKey: "keySounds")
        ambient = defaults.bool(forKey: "ambient")
        autoTitle = defaults.bool(forKey: "autoTitle")
        dailyGoal = defaults.integer(forKey: "dailyGoal")
        flowLock = defaults.bool(forKey: "flowLock")
        rhythm = defaults.bool(forKey: "rhythm")
        blogStyle = BlogStyle(rawValue: defaults.string(forKey: "blogStyle") ?? "") ?? .classic
        zenFullScreen = defaults.bool(forKey: "zenFullScreen")
        liveFormatting = defaults.bool(forKey: "liveFormatting")
        hideMarkup = defaults.bool(forKey: "hideMarkup")
        showFormatBar = defaults.bool(forKey: "showFormatBar")
        pomodoroEnabled = defaults.bool(forKey: "pomodoroEnabled")
        pomodoroWork = defaults.integer(forKey: "pomodoroWork")
        pomodoroShortBreak = defaults.integer(forKey: "pomodoroShortBreak")
        pomodoroLongBreak = defaults.integer(forKey: "pomodoroLongBreak")
        pomodoroLongEvery = defaults.integer(forKey: "pomodoroLongEvery")
        pomodoroAutoStart = defaults.bool(forKey: "pomodoroAutoStart")
        pomodoroZen = defaults.bool(forKey: "pomodoroZen")
        pomodoroBreakScreen = defaults.bool(forKey: "pomodoroBreakScreen")
    }

    func cycleFocus() {
        let all = FocusLevel.allCases
        focus = all[(all.firstIndex(of: focus)! + 1) % all.count]
    }
}
