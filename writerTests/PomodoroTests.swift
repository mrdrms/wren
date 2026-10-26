import Foundation
import Testing
@testable import writer

struct PomodoroTests {
    @Test func cyclesThroughWorkAndBreaks() {
        let longEvery = Preferences.shared.pomodoroLongEvery
        let autoStart = Preferences.shared.pomodoroAutoStart
        let pomodoro = Pomodoro()
        var ended: [(Pomodoro.Phase, Pomodoro.Phase)] = []
        pomodoro.onPhaseEnd = { ended.append(($0, $1)) }

        #expect(pomodoro.phase == .idle)
        pomodoro.start()
        #expect(pomodoro.phase == .work && pomodoro.isRunning)

        pomodoro.pause()
        #expect(!pomodoro.isRunning && pomodoro.remaining() > 0)
        pomodoro.resume()
        #expect(pomodoro.isRunning)

        for _ in 1..<longEvery {
            pomodoro.skip() // work → short break (breaks start on their own)
            #expect(pomodoro.phase == .shortBreak && pomodoro.isRunning)
            pomodoro.skip() // break → work
            #expect(pomodoro.phase == .work)
            #expect(pomodoro.isRunning == autoStart)
            if !autoStart { pomodoro.start() }
        }
        pomodoro.skip()
        #expect(pomodoro.phase == .longBreak)
        #expect(ended.count == (longEvery - 1) * 2 + 1)

        pomodoro.stop()
        #expect(pomodoro.phase == .idle && !pomodoro.isRunning && pomodoro.cycle == 0)
    }

    @Test func skippedSessionsDontCount() {
        let pomodoro = Pomodoro()
        let before = pomodoro.completedToday
        pomodoro.start()
        pomodoro.skip()
        #expect(pomodoro.completedToday == before)
        pomodoro.stop()
    }
}
