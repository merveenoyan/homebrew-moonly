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

// MARK: - LLM-inferred phase

/// How intense the current phase feels, based on the user's logged symptoms
/// and their personal history. Particularly useful within luteal, where early
/// days can feel mild and the last 5-7 days (PMS) can be significantly harder.
enum PhaseIntensity: String, Codable, CaseIterable {
    case low, moderate, high

    var label: String {
        switch self {
        case .low:      return "Mild"
        case .moderate: return "Moderate"
        case .high:     return "Intense"
        }
    }
}

/// The LLM's best guess at the user's current phase, derived from their
/// personal symptom/mood history rather than a fixed-day formula. Persisted
/// alongside logs so it survives restarts without re-running the model.
struct PhaseInference: Codable, Equatable {
    let phase: CyclePhase
    let intensity: PhaseIntensity
    let confidence: Double          // 0…1
    let reasoning: String           // one sentence the UI can show as a tooltip
    let predictedTransition: PredictedTransition?
    let generatedAt: Date

    /// How long ago this inference was produced — stale results should be
    /// refreshed after new log data or a new day.
    var ageInHours: Double {
        Date().timeIntervalSince(generatedAt) / 3600
    }
}

/// A single upcoming transition the model is most confident about.
struct PredictedTransition: Codable, Equatable {
    let toPhase: CyclePhase
    let estimatedDaysAway: Int
}

/// The full bundle of context handed to the recommender for one generation.
struct PromptContext {
    var summary: CycleSummary
    var today: Date
    var lastThreePeriodStarts: [Date]   // most recent first
    var forecast: [PhaseForecast]
    var previous: PreviousCycleInsight?
    var recent: [DailyLog]
    var inference: PhaseInference?
}
