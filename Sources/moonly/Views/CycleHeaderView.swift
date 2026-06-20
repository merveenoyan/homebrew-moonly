import SwiftUI

/// Top of the dropdown: where the user is in their cycle, at a glance.
struct CycleHeaderView: View {
    let summary: CycleSummary
    var inference: PhaseInference?

    /// The phase to display: prefer the LLM inference when confident enough.
    private var displayPhase: CyclePhase {
        if let inf = inference, inf.confidence >= 0.5 { return inf.phase }
        return summary.phase
    }

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f
    }()

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if summary.hasEnoughData {
                CycleRing(cycleDay: summary.cycleDay,
                          cycleLength: summary.cycleLength,
                          phase: displayPhase)
            } else {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: displayPhase.systemImage)
                        .foregroundStyle(displayPhase.tint)
                    Text(summary.hasEnoughData ? phaseTitle : "Welcome to Moonly")
                        .font(.headline)
                    if let inf = inference, inf.confidence >= 0.5, summary.hasEnoughData {
                        intensityBadge(inf.intensity)
                    }
                }
                Text(summary.hasEnoughData ? subtitle : "Log a period day below to start tracking.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let inf = inference, inf.confidence >= 0.5, summary.hasEnoughData {
                    Text(inf.reasoning)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var phaseTitle: String {
        "\(displayPhase.title) phase"
    }

    @ViewBuilder
    private func intensityBadge(_ intensity: PhaseIntensity) -> some View {
        let color: Color = switch intensity {
        case .low:      .green
        case .moderate: .orange
        case .high:     .red
        }
        Text(intensity.label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var subtitle: String {
        if let inf = inference, inf.confidence >= 0.5,
           let t = inf.predictedTransition {
            let transitionText: String
            if t.estimatedDaysAway <= 0 {
                transitionText = "\(t.toPhase.title) phase expected today"
            } else if t.estimatedDaysAway == 1 {
                transitionText = "\(t.toPhase.title) phase likely tomorrow"
            } else {
                transitionText = "\(t.toPhase.title) phase in ~\(t.estimatedDaysAway) days"
            }
            if let days = summary.daysUntilNextPeriod, days > 0, t.toPhase != .menstrual {
                return "\(transitionText) · period in \(days) days"
            }
            return transitionText
        }
        if let days = summary.daysUntilNextPeriod, let next = summary.nextPeriodStart {
            if days <= 0 { return "Period expected today" }
            if days == 1 { return "Period likely tomorrow" }
            return "Next period in \(days) days · \(Self.df.string(from: next))"
        }
        return summary.phase.blurb
    }
}
