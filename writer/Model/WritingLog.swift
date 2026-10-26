import Foundation
import Observation

/// Words written per day, which powers goals, streaks and the Journey heatmap.
@Observable
final class WritingLog {
    static let shared = WritingLog()

    private(set) var days: [String: Int]
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private init() {
        days = (defaults.dictionary(forKey: "writingLog") as? [String: Int]) ?? [:]
    }

    static func key(for date: Date) -> String { formatter.string(from: date) }

    func add(_ words: Int, on date: Date = .now) {
        guard words > 0 else { return }
        days[Self.key(for: date), default: 0] += words
        defaults.set(days, forKey: "writingLog")
    }

    func words(on date: Date) -> Int { days[Self.key(for: date)] ?? 0 }

    var today: Int { words(on: .now) }
    var total: Int { days.values.reduce(0, +) }
    var bestDay: Int { days.values.max() ?? 0 }

    /// Consecutive days with writing, ending today (or yesterday, so the streak
    /// isn't shown as broken before you've had a chance to write today).
    var streak: Int {
        let calendar = Calendar.current
        var date = Date.now
        if words(on: date) == 0 {
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        var count = 0
        while words(on: date) > 0 {
            count += 1
            date = calendar.date(byAdding: .day, value: -1, to: date)!
        }
        return count
    }
}
