import Foundation
import Observation

/// An optional Pomodoro rhythm: focused work sessions separated by short breaks,
/// with a longer break after every few sessions.
@Observable
final class Pomodoro {
    enum Phase: String {
        case idle, work, shortBreak, longBreak

        var isBreak: Bool { self == .shortBreak || self == .longBreak }
        var label: String {
            switch self {
            case .idle: "Pomodoro"
            case .work: "Focus"
            case .shortBreak: "Short break"
            case .longBreak: "Long break"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var endDate: Date?
    /// Set while paused, and when the next session is ready but waiting for you to start it.
    private(set) var pausedRemaining: TimeInterval?
    /// Work sessions finished in the current set (resets after a long break).
    private(set) var cycle = 0
    /// Sessions completed per day ("yyyy-MM-dd").
    private var log: [String: Int]
    /// Read fresh each time, so it resets at midnight even if the app stays open.
    var completedToday: Int { log[WritingLog.key(for: .now)] ?? 0 }

    /// Called when a phase ends: (the phase that finished, the phase that comes next).
    @ObservationIgnored var onPhaseEnd: ((Phase, Phase) -> Void)?
    @ObservationIgnored var onPhaseStart: ((Phase) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let prefs = Preferences.shared
    @ObservationIgnored private let defaults = UserDefaults.standard

    init() {
        log = UserDefaults.standard.dictionary(forKey: "pomodoroLog") as? [String: Int] ?? [:]
    }

    var isActive: Bool { phase != .idle }
    var isRunning: Bool { endDate != nil }

    func duration(of phase: Phase) -> TimeInterval {
        switch phase {
        case .idle: 0
        case .work: TimeInterval(prefs.pomodoroWork * 60)
        case .shortBreak: TimeInterval(prefs.pomodoroShortBreak * 60)
        case .longBreak: TimeInterval(prefs.pomodoroLongBreak * 60)
        }
    }

    func remaining(at date: Date = .now) -> TimeInterval {
        if let pausedRemaining { return pausedRemaining }
        guard let endDate else { return 0 }
        return max(0, endDate.timeIntervalSince(date))
    }

    func progress(at date: Date = .now) -> Double {
        let total = duration(of: phase)
        return total > 0 ? min(1, max(0, 1 - remaining(at: date) / total)) : 0
    }

    // MARK: Controls

    func start() {
        if isActive, pausedRemaining != nil { resume() } else { begin(.work) }
    }

    func pause() {
        guard let endDate else { return }
        pausedRemaining = max(0, endDate.timeIntervalSinceNow)
        self.endDate = nil
        task?.cancel()
    }

    func resume() {
        guard let remaining = pausedRemaining else { return }
        pausedRemaining = nil
        schedule(remaining)
        onPhaseStart?(phase)
    }

    func toggle() {
        if isRunning { pause() } else { start() }
    }

    func skip() {
        guard isActive else { return }
        finish(completed: false)
    }

    func stop() {
        task?.cancel()
        phase = .idle
        endDate = nil
        pausedRemaining = nil
        cycle = 0
    }

    // MARK: Engine

    private func begin(_ next: Phase) {
        phase = next
        pausedRemaining = nil
        schedule(duration(of: next))
        onPhaseStart?(next)
    }

    private func schedule(_ seconds: TimeInterval) {
        task?.cancel()
        endDate = Date.now.addingTimeInterval(seconds)
        task = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.finish(completed: true)
        }
    }

    private func finish(completed: Bool) {
        task?.cancel()
        let finished = phase
        let next: Phase
        switch finished {
        case .idle:
            return
        case .work:
            if completed { recordCompletion() }
            cycle += 1
            next = cycle % max(1, prefs.pomodoroLongEvery) == 0 ? .longBreak : .shortBreak
        case .shortBreak:
            next = .work
        case .longBreak:
            cycle = 0
            next = .work
        }
        endDate = nil
        pausedRemaining = nil
        // Breaks always start on their own; a new work session waits for you unless you opted in.
        if next.isBreak || prefs.pomodoroAutoStart {
            begin(next)
        } else {
            phase = next
            pausedRemaining = duration(of: next)
        }
        onPhaseEnd?(finished, next)
    }

    private func recordCompletion() {
        log[WritingLog.key(for: .now), default: 0] += 1
        defaults.set(log, forKey: "pomodoroLog")
    }
}
