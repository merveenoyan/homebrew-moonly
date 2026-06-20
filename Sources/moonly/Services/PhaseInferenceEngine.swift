import Foundation
import Combine

/// Uses the local LLM to infer the user's current cycle phase from their
/// personal symptom, mood, and energy patterns — rather than relying on the
/// fixed "cycle length − 14" heuristic alone.
///
/// The model sees full previous-cycle logs organized by cycle day, learns which
/// symptoms cluster in which phase *for this specific user*, and maps today's
/// logged data onto that personal fingerprint. It can distinguish early vs late
/// luteal intensity and catch cycles that don't follow textbook timing.
@MainActor
final class PhaseInferenceEngine: ObservableObject {
    @Published private(set) var inference: PhaseInference?
    @Published private(set) var isRunning = false

    private let llama: LlamaServer
    private static let cacheURL: URL = {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Moonly/phase_inference.json")
    }()

    init(llama: LlamaServer = .shared) {
        self.llama = llama
        loadCached()
    }

    /// Whether the cached inference is still fresh enough to display. Stale
    /// after 18 hours or if a new log entry has been added since generation.
    func isFresh(latestLogDate: Date?) -> Bool {
        guard let inf = inference else { return false }
        if inf.ageInHours > 18 { return false }
        if let logDate = latestLogDate, logDate > inf.generatedAt { return false }
        return true
    }

    // MARK: - Run inference

    /// Build the prompt from raw cycle data and ask the model.
    /// Requires at least one complete previous cycle (≥2 period starts) with
    /// logged symptom data to be useful — otherwise returns nil.
    func infer(store: CycleStore, on date: Date = Date()) async {
        let starts = store.periodStartDates.filter { $0 <= store.day(date) }
        guard starts.count >= 2 else { return }

        let heuristicSummary = store.summary(on: date)
        let previousCycles = buildPreviousCycleLogs(store: store, on: date)
        guard !previousCycles.isEmpty else { return }

        let currentCycleLogs = buildCurrentCycleLogs(store: store, on: date)

        let prompt = buildUserPrompt(
            heuristic: heuristicSummary,
            previousCycles: previousCycles,
            currentLogs: currentCycleLogs,
            periodStarts: starts,
            date: date
        )

        isRunning = true
        defer { isRunning = false }

        do {
            await llama.ensureRunning()
            guard llama.status.isUsable else {
                llama.stop()
                return
            }
            let text = try await llama.chat(
                system: Self.systemPrompt,
                user: prompt,
                temperature: 0.3,
                maxTokens: 400
            )
            llama.stop()

            if let parsed = Self.parse(text) {
                inference = parsed
                persistCache()
            }
        } catch {
            llama.stop()
        }
    }

    // MARK: - Previous cycle data extraction

    /// One cycle's worth of daily logs, keyed by cycle day.
    struct CycleLog {
        let cycleIndex: Int        // 1 = most recent complete cycle
        let length: Int
        let days: [(cycleDay: Int, log: DailyLog)]
    }

    /// Extract up to 3 most recent complete cycles with their per-day logs.
    private func buildPreviousCycleLogs(store: CycleStore, on date: Date) -> [CycleLog] {
        let cal = Calendar.current
        let starts = store.periodStartDates.filter { $0 <= store.day(date) }
        guard starts.count >= 2 else { return [] }

        var cycles: [CycleLog] = []
        let count = min(starts.count - 1, 3)

        for i in 0..<count {
            let startIdx = starts.count - 1 - i
            guard startIdx >= 1 else { break }
            let cycleStart = starts[startIdx - 1]
            let cycleEnd = cal.date(byAdding: .day, value: -1, to: starts[startIdx])!
            let length = (cal.dateComponents([.day], from: cycleStart, to: starts[startIdx]).day ?? 28)

            var days: [(Int, DailyLog)] = []
            var d = cycleStart
            while d <= cycleEnd {
                let cd = (cal.dateComponents([.day], from: cycleStart, to: d).day ?? 0) + 1
                if let log = store.logs[d] {
                    days.append((cd, log))
                }
                guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
                d = next
            }

            if !days.isEmpty {
                cycles.append(CycleLog(cycleIndex: i + 1, length: length, days: days))
            }
        }
        return cycles
    }

    /// Current (incomplete) cycle logs from last period start to today.
    private func buildCurrentCycleLogs(store: CycleStore, on date: Date) -> [(cycleDay: Int, log: DailyLog)] {
        let cal = Calendar.current
        guard let start = store.lastPeriodStart(onOrBefore: date) else { return [] }
        let today = store.day(date)

        var days: [(Int, DailyLog)] = []
        var d = start
        while d <= today {
            let cd = (cal.dateComponents([.day], from: start, to: d).day ?? 0) + 1
            if let log = store.logs[d] {
                days.append((cd, log))
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        return days
    }

    // MARK: - Prompt construction

    private func buildUserPrompt(
        heuristic: CycleSummary,
        previousCycles: [CycleLog],
        currentLogs: [(cycleDay: Int, log: DailyLog)],
        periodStarts: [Date],
        date: Date
    ) -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        var lines: [String] = []

        lines.append("TODAY: \(df.string(from: date)), cycle day \(heuristic.cycleDay)")
        lines.append("Heuristic phase (formula-based): \(heuristic.phase.title)")
        lines.append("Average cycle length: \(heuristic.cycleLength) days")
        lines.append("Average period length: \(heuristic.periodLength) days")

        let recentStarts = periodStarts.suffix(4).reversed().map { df.string(from: $0) }
        lines.append("Period starts (recent first): \(recentStarts.joined(separator: ", "))")

        lines.append("")

        for cycle in previousCycles {
            lines.append("── PREVIOUS CYCLE \(cycle.cycleIndex) (length: \(cycle.length) days) ──")
            for (cd, log) in cycle.days {
                lines.append(formatDayLog(cycleDay: cd, log: log))
            }
            lines.append("")
        }

        lines.append("── CURRENT CYCLE (in progress) ──")
        if currentLogs.isEmpty {
            lines.append("No symptoms logged yet this cycle.")
        } else {
            for (cd, log) in currentLogs {
                lines.append(formatDayLog(cycleDay: cd, log: log))
            }
        }

        lines.append("")
        lines.append("Based on this user's personal patterns, infer their current phase and intensity. Respond ONLY with the JSON object described in your instructions.")
        return lines.joined(separator: "\n")
    }

    private func formatDayLog(cycleDay: Int, log: DailyLog) -> String {
        var parts: [String] = ["Day \(cycleDay):"]
        if log.isPeriod {
            parts.append("BLEEDING" + (log.flow.map { " (\($0.label))" } ?? ""))
        }
        if !log.symptoms.isEmpty {
            parts.append(log.symptoms.map { $0.label }.sorted().joined(separator: ", "))
        }
        if let m = log.mood { parts.append("mood=\(m.label)") }
        if let e = log.energy { parts.append("energy=\(e.label)") }
        return parts.joined(separator: " ")
    }

    // MARK: - System prompt

    static let systemPrompt = """
    You are a cycle-phase inference engine. Your job is to determine which \
    menstrual cycle phase a person is CURRENTLY in, based on their personal \
    symptom history — not textbook averages.

    PHASE KNOWLEDGE (use as priors, but the user's own patterns take precedence):

    MENSTRUAL — Definitive marker: bleeding. Typical symptoms: cramps (especially \
    days 1-2), fatigue, lower back pain, headache. Usually 3-7 days.

    FOLLICULAR — Follows menstruation, before ovulation. Energy gradually climbs, \
    mood improves, motivation increases. Skin often clears. Variable length \
    (shorter in short cycles, longer in long ones).

    OVULATORY — Around ovulation (mid-cycle, but varies enormously between people). \
    Peak energy, confidence, sociability. Some get mild pelvic twinges \
    (mittelschmerz). Usually a 2-4 day window.

    LUTEAL — After ovulation, before next period. TWO DISTINCT SUB-PHASES:
      • Early luteal: relatively calm, mild energy dip, slight bloating may begin. \
    Functional and manageable.
      • Late luteal (PMS window, typically last 5-7 days before period): this is \
    where intensity spikes. Key markers: irritability, mood swings, anxiety, \
    bloating worsens, breast tenderness, cravings (carbs/chocolate), fatigue \
    paired with insomnia, acne flare-ups, digestive changes, difficulty \
    concentrating. NOT everyone gets all of these — learn WHICH ones this \
    specific user gets.

    YOUR TASK:
    1. Study the previous cycle(s) to learn THIS user's personal phase fingerprint: \
    which symptoms cluster on which cycle days FOR THEM.
    2. Look at what they've logged in the current cycle so far.
    3. Match today's position against their personal pattern to infer the phase.
    4. The heuristic phase is provided as a hint, but YOU MAY DISAGREE if the \
    symptom evidence points elsewhere. Short cycles ovulate earlier. Long cycles \
    have longer follicular phases. Some people's luteal symptoms start earlier \
    or later than average.

    INTENSITY GUIDELINES:
    - "low": few or no phase-typical symptoms today, or symptoms are mild
    - "moderate": some characteristic symptoms present, manageable
    - "high": multiple strong phase-typical symptoms (especially relevant for \
    late luteal: irritability + cravings + fatigue + bloating = high intensity)

    CONFIDENCE:
    - 0.9+: bleeding (menstrual is obvious) or strong multi-symptom match to \
    personal pattern
    - 0.7-0.9: good symptom alignment with personal history
    - 0.5-0.7: limited data or ambiguous signals
    - <0.5: mostly guessing — defer to heuristic

    Respond with ONLY a JSON object (no markdown, no commentary):
    {
      "phase": "menstrual" | "follicular" | "ovulatory" | "luteal",
      "intensity": "low" | "moderate" | "high",
      "confidence": 0.0-1.0,
      "reasoning": "one sentence explaining why, referencing the user's patterns",
      "transition": { "toPhase": "...", "daysAway": N } or null
    }
    """

    // MARK: - Parsing

    static func parse(_ raw: String) -> PhaseInference? {
        var cleaned = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}"), start < end else { return nil }
        cleaned = String(cleaned[start...end])

        // Fix smart quotes
        cleaned = cleaned.replacingOccurrences(of: "\u{201C}", with: "\"")
        cleaned = cleaned.replacingOccurrences(of: "\u{201D}", with: "\"")
        // Trailing commas
        cleaned = cleaned.replacingOccurrences(
            of: #",\s*([}\]])"#, with: "$1", options: .regularExpression)

        guard let data = cleaned.data(using: .utf8) else { return nil }

        struct Raw: Codable {
            let phase: String?
            let intensity: String?
            let confidence: Double?
            let reasoning: String?
            let transition: RawTransition?

            struct RawTransition: Codable {
                let toPhase: String?
                let daysAway: Int?
            }
        }

        guard let raw = try? JSONDecoder().decode(Raw.self, from: data),
              let phaseStr = raw.phase,
              let phase = CyclePhase(rawValue: phaseStr) else { return nil }

        let intensity = raw.intensity.flatMap { PhaseIntensity(rawValue: $0) } ?? .moderate
        let confidence = (raw.confidence ?? 0.5).clamped(to: 0...1)
        let reasoning = raw.reasoning ?? "Based on symptom pattern analysis."

        var transition: PredictedTransition?
        if let t = raw.transition,
           let toStr = t.toPhase,
           let toPhase = CyclePhase(rawValue: toStr),
           let days = t.daysAway, days >= 0 {
            transition = PredictedTransition(toPhase: toPhase, estimatedDaysAway: days)
        }

        return PhaseInference(
            phase: phase,
            intensity: intensity,
            confidence: confidence,
            reasoning: reasoning,
            predictedTransition: transition,
            generatedAt: Date()
        )
    }

    // MARK: - Persistence

    private func loadCached() {
        guard let json = DataEncryptor.readMigrating(from: Self.cacheURL),
              let cached = try? JSONDecoder.moonly.decode(PhaseInference.self, from: json) else { return }
        if cached.ageInHours < 24 {
            inference = cached
        }
    }

    private func persistCache() {
        guard let inf = inference,
              let encrypted = try? DataEncryptor.encrypt(inf) else { return }
        try? encrypted.write(to: Self.cacheURL, options: .atomic)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
