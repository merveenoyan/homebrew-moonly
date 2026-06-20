import Foundation
import Combine
import UserNotifications

/// One actionable suggestion shown in the dropdown.
struct Recommendation: Identifiable, Equatable {
    let id = UUID()
    var icon: String      // SF Symbol
    var title: String
    var body: String
}

/// Produces cycle-phase-aware, day-level recommendations.
///
/// Two layers:
///  1. A deterministic, evidence-informed **rule baseline** per phase — instant,
///     available before the model loads.
///  2. An **AI layer** that runs **once per day**: starts llama-server, generates
///     personalized recommendations, sends a macOS notification, then shuts the
///     server down. Falls back to the baseline on any failure. Not medical advice.
@MainActor
final class RecommendationEngine: ObservableObject {
    enum Source: Equatable { case rules, ai }

    @Published private(set) var items: [Recommendation] = []
    @Published private(set) var source: Source = .rules
    @Published private(set) var isGenerating = false
    @Published private(set) var note: String?

    private let llama: LlamaServer

    /// Key for persisting the last generation date so we only run once per day.
    private static let lastRunKey = "RecommendationEngine.lastRunDate"

    init(llama: LlamaServer = .shared) { self.llama = llama }

    /// Icons the model may choose from (also enforced when parsing).
    static let allowedIcons: Set<String> = [
        "figure.walk", "fork.knife", "bed.double.fill", "drop.fill", "heart.fill",
        "leaf.fill", "cup.and.saucer.fill", "brain.head.profile", "moon.zzz.fill",
        "sun.max.fill", "square.and.pencil", "house.fill", "person.2.fill",
        "bolt.fill", "calendar", "hands.sparkles.fill",
    ]

    // MARK: - Public API

    func showBaseline(for summary: CycleSummary) {
        items = Self.ruleBaseline(for: summary)
        source = .rules
        note = nil
    }

    /// Whether the model has already run today.
    private var hasRunToday: Bool {
        guard let last = UserDefaults.standard.object(forKey: Self.lastRunKey) as? Date else { return false }
        return Calendar.current.isDateInToday(last)
    }

    private func markRunToday() {
        UserDefaults.standard.set(Date(), forKey: Self.lastRunKey)
    }

    /// Load cached AI recommendations from disk (persisted from today's run).
    func loadCachedRecommendations() {
        guard let json = DataEncryptor.readMigrating(from: Self.cacheURL),
              let cached = try? JSONDecoder().decode([CachedRec].self, from: json) else { return }
        let recs = cached.map { Recommendation(icon: $0.icon, title: $0.title, body: $0.body) }
        if !recs.isEmpty {
            items = recs
            source = .ai
        }
    }

    /// Run the model once a day: start server, generate, notify, stop server.
    func generateOnceDaily(context: PromptContext) async {
        if items.isEmpty { showBaseline(for: context.summary) }

        // If we already ran today, just load cached results.
        if hasRunToday {
            loadCachedRecommendations()
            return
        }

        guard context.summary.hasEnoughData else {
            note = "Log a period start to unlock personalized guidance."
            return
        }

        isGenerating = true
        note = nil
        defer { isGenerating = false }

        do {
            await llama.ensureRunning()
            guard llama.status.isUsable else {
                llama.stop()
                source = .rules
                note = "Model couldn't start — showing general guidance."
                return
            }
            let text = try await llama.chat(
                system: Self.systemPrompt,
                user: Self.userPrompt(context),
                temperature: 0.7, maxTokens: 800
            )
            llama.stop()

            let parsed = Self.parse(text)
            if parsed.isEmpty {
                note = "Couldn't read the model's reply — showing general guidance."
            } else {
                items = parsed
                source = .ai
                markRunToday()
                cacheRecommendations(parsed)
                await sendNotification(parsed)
            }
        } catch {
            llama.stop()
            source = .rules
            note = "Personalized tips unavailable right now."
        }
    }

    /// Legacy generate for explicit refresh — also shuts server down after.
    func generate(context: PromptContext) async {
        if items.isEmpty { showBaseline(for: context.summary) }
        guard context.summary.hasEnoughData else {
            note = "Log a period start to unlock personalized guidance."
            return
        }

        isGenerating = true
        note = nil
        defer { isGenerating = false }

        do {
            await llama.ensureRunning()
            guard llama.status.isUsable else {
                llama.stop()
                source = .rules
                note = "Model couldn't start — showing general guidance."
                return
            }
            let text = try await llama.chat(
                system: Self.systemPrompt,
                user: Self.userPrompt(context),
                temperature: 0.7, maxTokens: 800
            )
            llama.stop()

            let parsed = Self.parse(text)
            if parsed.isEmpty {
                note = "Couldn't read the model's reply — showing general guidance."
            } else {
                items = parsed
                source = .ai
                markRunToday()
                cacheRecommendations(parsed)
                await sendNotification(parsed)
            }
        } catch {
            llama.stop()
            source = .rules
            note = "Personalized tips unavailable right now."
        }
    }

    // MARK: - Notification

    func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(_ recs: [Recommendation]) async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Moonly — Today's guidance"
        content.body = recs.map { "\($0.title): \($0.body)" }.joined(separator: "\n")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "moonly.daily.\(ISO8601DateFormatter().string(from: Date()))",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    // MARK: - Cache (so we can show AI results without re-running the model)

    private struct CachedRec: Codable { let icon: String; let title: String; let body: String }

    private static var cacheURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Moonly/recommendations.json")
    }

    private func cacheRecommendations(_ recs: [Recommendation]) {
        let items = recs.map { CachedRec(icon: $0.icon, title: $0.title, body: $0.body) }
        guard let encrypted = try? DataEncryptor.encrypt(items, encoder: JSONEncoder()) else { return }
        try? encrypted.write(to: Self.cacheURL, options: .atomic)
    }

    // MARK: - Prompting

    static let systemPrompt = """
    You are Moonly, a warm, concise menstrual-cycle companion that runs entirely \
    on the user's device. Your job is to tell the user concretely what to do \
    TODAY — how to spend their energy — based on where they are in their cycle, \
    what's coming next, and how they tended to feel at this same point last cycle.

    Use the previous-cycle pattern to anticipate today: if they were irritable or \
    low-energy at this point last month, gently say so and suggest a fitting plan \
    (e.g. protect focus time, keep the day light, stay in, journal). If energy was \
    high, encourage them to make the most of it (deep work, training, social plans).

    Rules:
    - You are NOT a doctor. Never diagnose, never name medications or dosages, \
    never make clinical claims. Suggest seeing a clinician for severe, unusual, or \
    persistent symptoms.
    - Be specific and practical. Each suggestion is a concrete action for today, \
    tied to the phase, the forecast, and the user's own patterns — not generic.
    - Respond ONLY with a JSON array of exactly 3 objects with keys "icon", \
    "title", "body". "icon" is one of: figure.walk, fork.knife, bed.double.fill, \
    drop.fill, heart.fill, leaf.fill, cup.and.saucer.fill, brain.head.profile, \
    moon.zzz.fill, sun.max.fill, square.and.pencil, house.fill, person.2.fill, \
    bolt.fill, calendar, hands.sparkles.fill. "title" is 2-4 words. "body" is one \
    warm, concrete sentence (max ~140 chars). No prose outside the JSON.
    """

    static func userPrompt(_ ctx: PromptContext) -> String {
        let df = DateFormatter(); df.dateFormat = "EEE, MMM d"
        let s = ctx.summary
        var lines: [String] = []

        lines.append("Today: \(df.string(from: ctx.today))")

        if ctx.lastThreePeriodStarts.isEmpty {
            lines.append("Last period starts: none logged yet")
        } else {
            let dates = ctx.lastThreePeriodStarts.map { df.string(from: $0) }.joined(separator: ", ")
            lines.append("Last period starts (most recent first): \(dates)")
        }
        lines.append("Average cycle: \(s.cycleLength) days · average period: \(s.periodLength) days")
        if let inf = ctx.inference, inf.confidence >= 0.5 {
            lines.append("Current: cycle day \(s.cycleDay)")
            lines.append("LLM-inferred phase: \(inf.phase.title) (intensity: \(inf.intensity.label), confidence: \(Int(inf.confidence * 100))%)")
            lines.append("Inference reasoning: \(inf.reasoning)")
            if let t = inf.predictedTransition {
                let when = t.estimatedDaysAway == 0 ? "today"
                    : t.estimatedDaysAway == 1 ? "tomorrow" : "in \(t.estimatedDaysAway) days"
                lines.append("Predicted next transition: \(t.toPhase.title) \(when)")
            }
        } else {
            lines.append("Current: cycle day \(s.cycleDay), \(s.phase.title) phase — \(s.phase.blurb)")
        }

        // Forecast of upcoming phase transitions.
        if !ctx.forecast.isEmpty {
            lines.append("Upcoming phases:")
            for f in ctx.forecast {
                let when = f.daysAway == 0 ? "today"
                    : f.daysAway == 1 ? "tomorrow" : "in \(f.daysAway) days"
                lines.append("  - \(f.phase.title) begins \(df.string(from: f.startDate)) (\(when))")
            }
        }

        // Previous-cycle pattern — the differentiator.
        if let prev = ctx.previous {
            if !prev.atSamePoint.isEmpty || prev.moodAtSamePoint != nil {
                var bits: [String] = []
                if let m = prev.moodAtSamePoint { bits.append("mood: \(m.label)") }
                if !prev.atSamePoint.isEmpty {
                    bits.append("symptoms: " + prev.atSamePoint.map { $0.label }.joined(separator: ", "))
                }
                lines.append("At this same point last cycle (\(prev.sameWindowDescription)): " + bits.joined(separator: "; "))
            }
            let phaseBits = prev.symptomsByPhase.compactMap { (phase, counts) -> String? in
                guard !counts.isEmpty else { return nil }
                let top = counts.sorted { $0.value > $1.value }.prefix(3)
                    .map { "\($0.key.label)×\($0.value)" }.joined(separator: ", ")
                let mood = prev.moodByPhase[phase].map { " (mood: \($0.label))" } ?? ""
                return "\(phase.title): \(top)\(mood)"
            }
            if !phaseBits.isEmpty {
                lines.append("Last cycle by phase — " + phaseBits.joined(separator: " · "))
            }
        } else {
            lines.append("No complete previous cycle on record yet.")
        }

        // This cycle so far.
        let recentSymptoms = ctx.recent.flatMap { Array($0.symptoms) }
        let counts = Dictionary(grouping: recentSymptoms, by: { $0 }).mapValues { $0.count }
        if counts.isEmpty {
            lines.append("Recent symptoms (last 10 days): none logged")
        } else {
            let top = counts.sorted { $0.value > $1.value }
                .map { "\($0.key.label)×\($0.value)" }.joined(separator: ", ")
            lines.append("Recent symptoms (last 10 days): \(top)")
        }
        if let mood = ctx.recent.first?.mood { lines.append("Latest mood: \(mood.label)") }
        if let energy = ctx.recent.first?.energy { lines.append("Latest energy: \(energy.label)") }

        lines.append("")
        lines.append("Tell me 3 concrete things to do today, as the specified JSON array.")
        return lines.joined(separator: "\n")
    }

    // MARK: - Parsing

    /// Pull a JSON array out of the model reply, tolerating code fences/extra text.
    static func parse(_ raw: String) -> [Recommendation] {
        #if DEBUG
        let debugURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Moonly/last_model_response.txt")
        #endif

        // Strip markdown code fences if present.
        var cleaned = raw
        cleaned = cleaned.replacingOccurrences(of: "```json", with: "")
        cleaned = cleaned.replacingOccurrences(of: "```", with: "")

        guard let start = cleaned.firstIndex(of: "["),
              let end = cleaned.lastIndex(of: "]"), start < end else {
            #if DEBUG
            try? raw.write(to: debugURL, atomically: true, encoding: .utf8)
            #endif
            return []
        }
        var json = String(cleaned[start...end])

        // Fix common model quirks: smart quotes → straight quotes, trailing commas.
        json = json.replacingOccurrences(of: "\u{201C}", with: "\"")
        json = json.replacingOccurrences(of: "\u{201D}", with: "\"")
        json = json.replacingOccurrences(of: "\u{2018}", with: "'")
        json = json.replacingOccurrences(of: "\u{2019}", with: "'")
        // Remove trailing commas before ] or }
        json = json.replacingOccurrences(
            of: #",\s*([}\]])"#, with: "$1",
            options: .regularExpression)

        struct Item: Codable { let icon: String?; let title: String?; let body: String? }
        guard let data = json.data(using: .utf8),
              let items = try? JSONDecoder().decode([Item].self, from: data) else {
            #if DEBUG
            try? raw.write(to: debugURL, atomically: true, encoding: .utf8)
            #endif
            return []
        }

        let result = items.prefix(3).compactMap { item -> Recommendation? in
            guard let title = item.title, !title.isEmpty,
                  let body = item.body, !body.isEmpty else { return nil }
            return Recommendation(
                icon: Self.allowedIcons.contains(item.icon ?? "") ? item.icon! : "sparkles",
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                body: body.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        #if DEBUG
        if result.isEmpty {
            try? raw.write(to: debugURL, atomically: true, encoding: .utf8)
        }
        #endif
        return result
    }

    // MARK: - Rule baseline (day-action oriented)

    static func ruleBaseline(for summary: CycleSummary) -> [Recommendation] {
        switch summary.phase {
        case .menstrual:
            return [
                .init(icon: "house.fill", title: "Keep it gentle",
                      body: "Energy is at its lowest — favor low-stakes tasks and rest where you can."),
                .init(icon: "drop.fill", title: "Replenish iron",
                      body: "Lean red meat, lentils, or leafy greens help offset menstrual iron loss."),
                .init(icon: "figure.walk", title: "Light movement",
                      body: "A short walk or gentle yoga eases cramps better than sitting still."),
            ]
        case .follicular:
            return [
                .init(icon: "bolt.fill", title: "Front-load deep work",
                      body: "Rising estrogen lifts focus and drive — tackle your hardest tasks now."),
                .init(icon: "figure.walk", title: "Train harder",
                      body: "Strength and stamina climb this week; a good window to push intensity."),
                .init(icon: "fork.knife", title: "Fuel the build",
                      body: "Lean protein and complex carbs support the energy upswing."),
            ]
        case .ovulatory:
            return [
                .init(icon: "person.2.fill", title: "Make plans",
                      body: "Confidence and sociability often peak now — schedule the big conversations."),
                .init(icon: "sun.max.fill", title: "Ride the peak",
                      body: "Energy crests today; lean into active, outward-facing work."),
                .init(icon: "leaf.fill", title: "Anti-inflammatory plate",
                      body: "Colorful veg, omega-3s, and fiber support hormone balance around ovulation."),
            ]
        case .luteal:
            return [
                .init(icon: "house.fill", title: "Plan a lighter day",
                      body: "Patience and energy dip premenstrually — keep today low-stakes and protect your time."),
                .init(icon: "square.and.pencil", title: "Journal it out",
                      body: "Irritability is common now; a few minutes writing can take the edge off."),
                .init(icon: "moon.zzz.fill", title: "Protect sleep",
                      body: "Progesterone can disrupt rest; wind down early and keep the room cool."),
            ]
        }
    }
}
