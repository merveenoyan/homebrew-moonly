import SwiftUI

/// The recommendations block: instant rule-based guidance, upgraded in place by
/// the local model when it's ready.
struct RecommendationCard: View {
    @EnvironmentObject var engine: RecommendationEngine
    @EnvironmentObject var llama: LlamaServer
    let context: PromptContext

    private var summary: CycleSummary { context.summary }
    private var displayPhase: CyclePhase {
        if let inf = context.inference, inf.confidence >= 0.5 { return inf.phase }
        return summary.phase
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "For you today")
                sourceBadge
                Spacer()
                Button {
                    Task { await engine.generate(context: context) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(engine.isGenerating || !llamaActionable)
                .help("Regenerate suggestions")
            }

            if let next = context.forecast.first(where: { $0.daysAway > 0 }) {
                HStack(spacing: 5) {
                    Image(systemName: next.phase.systemImage)
                        .foregroundStyle(next.phase.tint)
                    Text("\(next.phase.title) phase begins \(forecastWhen(next.daysAway))")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.bottom, 2)
            }

            ForEach(engine.items) { rec in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: rec.icon)
                        .font(.body)
                        .foregroundStyle(displayPhase.tint)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rec.title).font(.callout.weight(.semibold))
                        Text(rec.body).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            statusFooter
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.04)))
    }

    // MARK: - Pieces

    @ViewBuilder private var sourceBadge: some View {
        if engine.isGenerating {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Thinking…").font(.caption2).foregroundStyle(.secondary)
            }
        } else if engine.source == .ai {
            Label("On-device AI", systemImage: "sparkles")
                .font(.caption2).foregroundStyle(displayPhase.tint)
                .labelStyle(.titleAndIcon)
        }
    }

    @ViewBuilder private var statusFooter: some View {
        if let note = engine.note {
            Text(note).font(.caption2).foregroundStyle(.secondary)
        }
        switch llama.status {
        case .starting:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(llama.detail ?? "Starting on-device model…")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        case .failed(let msg):
            Text(msg).font(.caption2).foregroundStyle(.orange)
        default:
            Text("Not medical advice · everything stays on this Mac")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func forecastWhen(_ days: Int) -> String {
        days == 1 ? "tomorrow" : "in \(days) days"
    }

    private var llamaActionable: Bool {
        switch llama.status { case .starting, .generating: return false; default: return true }
    }
}
