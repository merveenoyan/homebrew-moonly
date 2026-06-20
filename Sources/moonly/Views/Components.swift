import SwiftUI

/// A small uppercase section heading.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}

/// A selectable pill used for symptoms, mood, and energy.
struct Chip: View {
    let label: String
    var leading: String? = nil       // emoji
    var systemImage: String? = nil
    let isOn: Bool
    var tint: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let leading { Text(leading) }
                if let systemImage { Image(systemName: systemImage) }
                Text(label)
            }
            .font(.callout)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isOn ? tint.opacity(0.20) : Color.primary.opacity(0.06))
            )
            .overlay(
                Capsule().strokeBorder(isOn ? tint.opacity(0.65) : .clear, lineWidth: 1)
            )
            .foregroundStyle(isOn ? tint : .primary)
        }
        .buttonStyle(.plain)
    }
}

/// A row of dots showing flow intensity (1–4 filled).
struct FlowDots: View {
    let level: Int
    var tint: Color = CyclePhase.menstrual.tint
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill(i < level ? tint : Color.primary.opacity(0.15))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

/// A circular cycle-progress ring with the current day in the center.
struct CycleRing: View {
    let cycleDay: Int
    let cycleLength: Int
    let phase: CyclePhase

    private var progress: Double {
        guard cycleLength > 0 else { return 0 }
        return min(1, max(0, Double(cycleDay) / Double(cycleLength)))
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: 6)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(phase.tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(cycleDay)")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("day").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(width: 64, height: 64)
        .animation(.easeInOut, value: progress)
    }
}
