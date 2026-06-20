import Foundation

/// A single day's entry. Days with no data simply have no `DailyLog`.
struct DailyLog: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// Normalized to the start of the calendar day (local time).
    var date: Date
    /// Whether the user is bleeding today. Used to detect period starts.
    var isPeriod: Bool = false
    var flow: Flow? = nil
    var symptoms: Set<Symptom> = []
    var mood: Mood? = nil
    var energy: Energy? = nil
    var notes: String = ""

    /// True when the day carries no information and can be pruned on save.
    var isEmpty: Bool {
        !isPeriod && flow == nil && symptoms.isEmpty
            && mood == nil && energy == nil
            && notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
