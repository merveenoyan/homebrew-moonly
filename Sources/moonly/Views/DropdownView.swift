import SwiftUI
import AppKit

/// The menu-bar dropdown. Composes the cycle header, the quick logger, the
/// recommendation card, and a short history strip.
struct DropdownView: View {
    @EnvironmentObject var store: CycleStore
    @EnvironmentObject var llama: LlamaServer
    @StateObject private var engine = RecommendationEngine()
    @StateObject private var phaseEngine = PhaseInferenceEngine()

    private var today: Date { Date() }
    private var context: PromptContext {
        store.promptContext(on: today, inference: phaseEngine.inference)
    }
    private var summary: CycleSummary { context.summary }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            CycleHeaderView(summary: summary, inference: phaseEngine.inference)

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

            let latestLog = store.recentLogs(days: 1, on: today).first?.date
            if !phaseEngine.isFresh(latestLogDate: latestLog) {
                await phaseEngine.infer(store: store, on: today)
            }

            let freshCtx = store.promptContext(on: today, inference: phaseEngine.inference)
            await engine.generateOnceDaily(context: freshCtx)
        }
        .onChange(of: store.logs) {
            Task {
                await phaseEngine.infer(store: store, on: today)
            }
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
