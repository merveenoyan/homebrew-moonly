import SwiftUI

/// Top of the dropdown: where the user is in their cycle, at a glance.
struct CycleHeaderView: View {
    let summary: CycleSummary

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if summary.hasEnoughData {
                CycleRing(cycleDay: summary.cycleDay,
                          cycleLength: summary.cycleLength,
                          phase: summary.phase)
            } else {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: summary.phase.systemImage)
                        .foregroundStyle(summary.phase.tint)
                    Text(summary.hasEnoughData ? "\(summary.phase.title) phase" : "Welcome to Moonly")
                        .font(.headline)
                }
                Text(summary.hasEnoughData ? subtitle : "Log a period day below to start tracking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    private var subtitle: String {
        if let days = summary.daysUntilNextPeriod, let next = summary.nextPeriodStart {
            if days <= 0 { return "Period expected today" }
            if days == 1 { return "Period likely tomorrow" }
            return "Next period in \(days) days · \(Self.df.string(from: next))"
        }
        return summary.phase.blurb
    }
}
