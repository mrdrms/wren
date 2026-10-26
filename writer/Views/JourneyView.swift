import SwiftUI

/// The Writing Garden: streaks and history, grown rather than charted.
struct JourneyView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let log = model.log
        let theme = model.prefs.theme
        let goal = model.prefs.dailyGoal
        ZStack {
            AtmosphereView(theme: theme)
            theme.bg.opacity(0.55)

            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Writing Garden")
                            .font(.system(size: 30, weight: .semibold, design: .serif))
                            .foregroundStyle(theme.fg)
                        Text(encouragement)
                            .font(.system(.body, design: .serif).italic())
                            .foregroundStyle(theme.mutedColor)
                    }
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.glassProminent)
                        .tint(theme.accentColor)
                }

                HStack(spacing: 0) {
                    stat(log.streak == 1 ? "1" : "\(log.streak)", log.streak == 1 ? "day in a row" : "days in a row")
                    divider
                    stat(log.today.formatted(), "words today")
                    divider
                    stat(log.bestDay.formatted(), "best day")
                    divider
                    stat(log.total.formatted(), "words all time")
                }

                VStack(alignment: .leading, spacing: 12) {
                    GardenView(log: log, goal: goal, theme: theme)
                        .frame(height: 250)
                        .padding(18)
                        .background(theme.panelColor.opacity(0.65), in: .rect(cornerRadius: 22))
                        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(theme.mutedColor.opacity(0.18)))

                    HStack(spacing: 18) {
                        ForEach(0..<5) { level in
                            HStack(spacing: 6) {
                                PlantView(level: level, theme: theme, animated: false)
                                    .frame(width: 30, height: 38)
                                Text(GardenArt.labels[level]).font(.caption).foregroundStyle(theme.mutedColor)
                            }
                        }
                        Spacer()
                        Text("Each plant is a day. Reach \(goal.formatted()) words to make it bloom.")
                            .font(.caption.italic())
                            .foregroundStyle(theme.mutedColor)
                    }
                }

                HStack {
                    Stepper("Daily goal: \(goal.formatted()) words", value: Bindable(model.prefs).dailyGoal, in: 50...20_000, step: 50)
                        .fixedSize()
                    Spacer()
                    if model.pomodoro.completedToday > 0 {
                        Text("\(model.pomodoro.completedToday) focus sessions today").font(.callout).foregroundStyle(theme.mutedColor)
                    }
                }
            }
            .padding(30)
        }
        .frame(width: 860, height: 600)
        .preferredColorScheme(theme.colorScheme)
    }

    private var divider: some View {
        Rectangle().fill(model.prefs.theme.mutedColor.opacity(0.25)).frame(width: 1, height: 44)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        let theme = model.prefs.theme
        return VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 34, weight: .light, design: .serif))
                .monospacedDigit()
                .foregroundStyle(theme.fg)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(theme.mutedColor)
        }
        .frame(maxWidth: .infinity)
    }

    private var encouragement: String {
        let streak = model.log.streak
        switch streak {
        case 0: return "Every garden starts with a single seed. Plant one today."
        case 1...2: return "Something is sprouting. Come back tomorrow and water it."
        case 3...6: return "Your garden is taking root. Keep tending it."
        case 7...29: return "\(streak) days of growth. This is what a writing habit looks like."
        default: return "\(streak) days. Your garden is in full bloom."
        }
    }
}
