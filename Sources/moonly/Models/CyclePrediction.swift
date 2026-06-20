import Foundation

/// A predicted upcoming phase transition with its date.
struct PhaseForecast: Equatable, Identifiable {
    var id: String { "\(phase.rawValue)-\(Int(startDate.timeIntervalSince1970))" }
    let phase: CyclePhase
    let startDate: Date
    let daysAway: Int   // 0 = today, >0 = upcoming
}

/// What the previous (most recently completed) cycle looked like — the basis for
/// anticipating how the user may feel at the same point this cycle.
struct PreviousCycleInsight: Equatable {
    /// Symptoms grouped by the phase they occurred in, with counts.
    var symptomsByPhase: [CyclePhase: [Symptom: Int]]
    /// Dominant mood per phase, if logged.
    var moodByPhase: [CyclePhase: Mood]
    /// Symptoms logged around the same cycle day last time (±2 days).
    var atSamePoint: [Symptom]
    var moodAtSamePoint: Mood?
    /// Human-readable window, e.g. "cycle days 20–24".
    var sameWindowDescription: String
}

/// The full bundle of context handed to the recommender for one generation.
struct PromptContext {
    var summary: CycleSummary
    var today: Date
    var lastThreePeriodStarts: [Date]   // most recent first
    var forecast: [PhaseForecast]
    var previous: PreviousCycleInsight?
    var recent: [DailyLog]
}
