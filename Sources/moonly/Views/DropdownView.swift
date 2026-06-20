import SwiftUI
import AppKit

/// The menu-bar dropdown. Composes the cycle header, the quick logger, the
/// recommendation card, and a short history strip.
struct DropdownView: View {
    @EnvironmentObject var store: CycleStore
    @EnvironmentObject var llama: LlamaServer
    @StateObject private var engine = RecommendationEngine()

    // The dropdown always logs/looks at "now".
    private var today: Date { Date() }
    private var context: PromptContext { store.promptContext(on: today) }
    private var summary: CycleSummary { context.summary }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CycleHeaderView(summary: summary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    RecommendationCard(context: context)
                        .environmentObject(engine)
                    SymptomLoggerView(date: today)
                    HistoryView(endDate: today)
                }
                .padding(.bottom, 4)
            }
            .frame(minHeight: 420, maxHeight: 520)

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 420)
        .task {
            engine.requestNotificationPermission()
            let ctx = context
            engine.showBaseline(for: ctx.summary)
            await engine.generateOnceDaily(context: ctx)
        }
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill").font(.caption2)
                Text("On-device · private").font(.caption2)
            }
            .foregroundStyle(.secondary)
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
