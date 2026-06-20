import Foundation
import Combine

/// A read-only snapshot of where the user is in their cycle on a given day,
/// passed to the UI and the recommender so neither has to re-derive it.
struct CycleSummary: Equatable {
    var referenceDate: Date
    var cycleDay: Int
    var cycleLength: Int
    var periodLength: Int
    var phase: CyclePhase
    var lastPeriodStart: Date?
    var nextPeriodStart: Date?
    var ovulationDate: Date?
    var fertileWindow: ClosedRange<Date>?
    var hasEnoughData: Bool

    var daysUntilNextPeriod: Int? {
        guard let next = nextPeriodStart else { return nil }
        return Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: referenceDate), to: next).day
    }
}

/// Owns all cycle data and persistence. Single source of truth for the app.
///
/// Data is stored as a plain JSON file in Application Support and never leaves
/// the machine. Cycle/period lengths are learned from the user's own history,
/// with sensible defaults until enough data accrues.
@MainActor
final class CycleStore: ObservableObject {
    static let shared = CycleStore()

    /// Logs keyed by start-of-day. Days without data are absent.
    @Published private(set) var logs: [Date: DailyLog] = [:]

    /// User-defined custom symptoms (persisted alongside logs).
    @Published private(set) var customSymptoms: [Symptom] = []

    /// Optional manual overrides; when nil the value is learned from history.
    @Published var cycleLengthOverride: Int? = nil
    @Published var periodLengthOverride: Int? = nil

    private let calendar = Calendar.current
    private let storeURL: URL

    // MARK: - Defaults / clamps

    private static let defaultCycleLength = 28
    private static let defaultPeriodLength = 5
    private static let cycleLengthRange = 21...40
    private static let periodLengthRange = 2...10

    private init() {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Moonly", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)
        self.storeURL = base.appendingPathComponent("data.json")
        load()
    }

    // MARK: - Day access & mutation

    func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    func log(on date: Date) -> DailyLog {
        logs[day(date)] ?? DailyLog(date: day(date))
    }

    /// Mutate (or create) the log for `date`, then persist. Empty logs are pruned.
    func mutate(_ date: Date, _ transform: (inout DailyLog) -> Void) {
        let key = day(date)
        var entry = logs[key] ?? DailyLog(date: key)
        transform(&entry)
        if entry.isEmpty {
            logs[key] = nil
        } else {
            logs[key] = entry
        }
        save()
    }

    func toggleSymptom(_ symptom: Symptom, on date: Date) {
        mutate(date) { log in
            if log.symptoms.contains(symptom) { log.symptoms.remove(symptom) }
            else { log.symptoms.insert(symptom) }
        }
    }

    func setPeriod(_ on: Bool, flow: Flow?, on date: Date) {
        mutate(date) { log in
            log.isPeriod = on
            log.flow = on ? (flow ?? log.flow ?? .medium) : nil
        }
    }

    func setMood(_ mood: Mood?, on date: Date) {
        mutate(date) { $0.mood = $0.mood == mood ? nil : mood }
    }

    func setEnergy(_ energy: Energy?, on date: Date) {
        mutate(date) { $0.energy = $0.energy == energy ? nil : energy }
    }

    /// Add a user-defined custom symptom to the catalog.
    func addCustomSymptom(_ name: String) {
        let symptom = Symptom.custom(name)
        guard !customSymptoms.contains(symptom) else { return }
        customSymptoms.append(symptom)
        save()
    }

    /// All available symptoms: built-in + user-defined.
    var allSymptoms: [Symptom] {
        Symptom.builtIn + customSymptoms
    }

    // MARK: - Derived cycle data

    /// All days the user marked as bleeding, ascending.
    private var periodDays: [Date] {
        logs.values.filter { $0.isPeriod }.map { $0.date }.sorted()
    }

    /// First day of each distinct bleeding episode (a day with no bleeding the
    /// day before), ascending.
    var periodStartDates: [Date] {
        let days = Set(periodDays)
        return periodDays.filter { d in
            let prior = calendar.date(byAdding: .day, value: -1, to: d)!
            return !days.contains(prior)
        }
    }

    /// Most recent period start on or before `date`.
    func lastPeriodStart(onOrBefore date: Date) -> Date? {
        let ref = day(date)
        return periodStartDates.last { $0 <= ref }
    }

    var cycleLength: Int {
        if let o = cycleLengthOverride { return o.clamped(to: Self.cycleLengthRange) }
        let starts = periodStartDates
        guard starts.count >= 2 else { return Self.defaultCycleLength }
        // Average the most recent gaps (up to 6) for responsiveness.
        let gaps = zip(starts.dropFirst(), starts).map {
            calendar.dateComponents([.day], from: $1, to: $0).day ?? Self.defaultCycleLength
        }
        let recent = gaps.suffix(6)
        let avg = Double(recent.reduce(0, +)) / Double(recent.count)
        return Int(avg.rounded()).clamped(to: Self.cycleLengthRange)
    }

    var periodLength: Int {
        if let o = periodLengthOverride { return o.clamped(to: Self.periodLengthRange) }
        let runs = periodRunLengths()
        guard !runs.isEmpty else { return Self.defaultPeriodLength }
        let avg = Double(runs.reduce(0, +)) / Double(runs.count)
        return Int(avg.rounded()).clamped(to: Self.periodLengthRange)
    }

    private func periodRunLengths() -> [Int] {
        let days = periodDays
        guard !days.isEmpty else { return [] }
        var runs: [Int] = []
        var current = 1
        for i in 1..<max(days.count, 1) {
            let prev = days[i - 1], cur = days[i]
            if calendar.dateComponents([.day], from: prev, to: cur).day == 1 {
                current += 1
            } else {
                runs.append(current); current = 1
            }
        }
        runs.append(current)
        return runs
    }

    /// Cycle day (1-based) on `date`, or nil if no period has been logged yet.
    func cycleDay(on date: Date) -> Int? {
        guard let start = lastPeriodStart(onOrBefore: date) else { return nil }
        let days = calendar.dateComponents([.day], from: start, to: day(date)).day ?? 0
        return days + 1
    }

    /// Phase for a given 1-based cycle day, individualized by the user's lengths.
    func phase(forCycleDay d: Int) -> CyclePhase {
        phase(forCycleDay: d, cycleLength: cycleLength)
    }

    /// Phase for a cycle day within a cycle of a specific length — used when
    /// classifying days in a *past* cycle that had its own length.
    func phase(forCycleDay d: Int, cycleLength L: Int) -> CyclePhase {
        let P = periodLength
        let ovulation = max(10, L - 14)
        if d <= P { return .menstrual }
        if d < ovulation - 1 { return .follicular }
        if d <= ovulation + 1 { return .ovulatory }
        return .luteal
    }

    // MARK: - Summary & predictions

    func summary(on date: Date = Date()) -> CycleSummary {
        let ref = day(date)
        let L = cycleLength
        let P = periodLength
        let start = lastPeriodStart(onOrBefore: ref)
        let cd = cycleDay(on: ref)
        let phase: CyclePhase = cd.map { self.phase(forCycleDay: $0) } ?? .follicular

        var next: Date?
        var ovulation: Date?
        var fertile: ClosedRange<Date>?
        if let start {
            next = calendar.date(byAdding: .day, value: L, to: start)
            let ovDay = max(10, L - 14)
            if let ov = calendar.date(byAdding: .day, value: ovDay - 1, to: start) {
                ovulation = ov
                if let fStart = calendar.date(byAdding: .day, value: -5, to: ov),
                   let fEnd = calendar.date(byAdding: .day, value: 1, to: ov) {
                    fertile = fStart...fEnd
                }
            }
        }

        return CycleSummary(
            referenceDate: ref,
            cycleDay: cd ?? 0,
            cycleLength: L,
            periodLength: P,
            phase: phase,
            lastPeriodStart: start,
            nextPeriodStart: next,
            ovulationDate: ovulation,
            fertileWindow: fertile,
            hasEnoughData: start != nil
        )
    }

    var currentPhase: CyclePhase { summary().phase }

    /// Logs for the last `n` days, most recent first — context for the recommender.
    func recentLogs(days n: Int = 7, on date: Date = Date()) -> [DailyLog] {
        (0..<n).compactMap { offset in
            let d = calendar.date(byAdding: .day, value: -offset, to: day(date))!
            return logs[d]
        }
    }

    /// Menu-bar glyph: a moon phase that tracks progress through the cycle, so
    /// "full moon" lands around ovulation. Falls back to a plain moon pre-data.
    var menuBarSymbolName: String {
        let s = summary()
        guard s.hasEnoughData, s.cycleLength > 0 else { return "moon" }
        let p = Double(max(0, s.cycleDay - 1)) / Double(s.cycleLength)
        let phases = [
            "moonphase.new.moon",
            "moonphase.waxing.crescent",
            "moonphase.first.quarter",
            "moonphase.waxing.gibbous",
            "moonphase.full.moon",
            "moonphase.waning.gibbous",
            "moonphase.last.quarter",
            "moonphase.waning.crescent",
        ]
        let idx = min(phases.count - 1, max(0, Int(p * Double(phases.count))))
        return phases[idx]
    }

    // MARK: - Predictions & context

    /// The most recent `n` period start dates, most recent first.
    func lastPeriodStarts(_ n: Int, onOrBefore date: Date = Date()) -> [Date] {
        Array(periodStartDates.filter { $0 <= day(date) }.suffix(n).reversed())
    }

    /// The next upcoming start of each phase (this cycle and the next), so the
    /// UI and the model can say "luteal begins in N days". Sorted by date.
    func upcomingPhases(on date: Date = Date()) -> [PhaseForecast] {
        guard let start = lastPeriodStart(onOrBefore: date) else { return [] }
        let L = cycleLength
        let P = periodLength
        let ov = max(10, L - 14)
        // Cycle day on which each phase begins.
        let phaseStartDay: [(CyclePhase, Int)] = [
            (.menstrual, 1),
            (.follicular, P + 1),
            (.ovulatory, ov - 1),
            (.luteal, ov + 2),
        ]
        let today = day(date)

        var events: [PhaseForecast] = []
        for cycleIndex in 0...1 {
            guard let anchor = calendar.date(byAdding: .day, value: cycleIndex * L, to: start) else { continue }
            for (phase, cd) in phaseStartDay {
                guard let d = calendar.date(byAdding: .day, value: cd - 1, to: anchor) else { continue }
                let days = calendar.dateComponents([.day], from: today, to: d).day ?? 0
                if days >= 0 { events.append(PhaseForecast(phase: phase, startDate: d, daysAway: days)) }
            }
        }

        // Keep the next occurrence of each distinct phase.
        var seen = Set<CyclePhase>()
        return events.sorted { $0.startDate < $1.startDate }
            .filter { seen.insert($0.phase).inserted }
    }

    /// Build an insight from the previous completed cycle (between the last two
    /// period starts): what was felt in each phase, and specifically around the
    /// same cycle day the user is on now.
    func previousCycleInsight(on date: Date = Date()) -> PreviousCycleInsight? {
        let starts = periodStartDates.filter { $0 <= day(date) }
        guard starts.count >= 2 else { return nil }
        let lastStart = starts[starts.count - 1]
        let prevStart = starts[starts.count - 2]
        guard let endPrev = calendar.date(byAdding: .day, value: -1, to: lastStart) else { return nil }
        let prevLen = calendar.dateComponents([.day], from: prevStart, to: lastStart).day ?? cycleLength

        var symptomsByPhase: [CyclePhase: [Symptom: Int]] = [:]
        var moodTally: [CyclePhase: [Mood: Int]] = [:]

        var d = prevStart
        while d <= endPrev {
            if let log = logs[d] {
                let cd = (calendar.dateComponents([.day], from: prevStart, to: d).day ?? 0) + 1
                let phase = phase(forCycleDay: cd, cycleLength: prevLen)
                for s in log.symptoms { symptomsByPhase[phase, default: [:]][s, default: 0] += 1 }
                if let m = log.mood { moodTally[phase, default: [:]][m, default: 0] += 1 }
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }
        let moodByPhase = moodTally.compactMapValues { $0.max { $0.value < $1.value }?.key }

        // Same-point lookup: current cycle day ±2 within the previous cycle.
        let cd0 = cycleDay(on: date) ?? 1
        var samePointSymptoms: [Symptom] = []
        var samePointMood: [Mood: Int] = [:]
        for delta in -2...2 {
            let cd = cd0 + delta
            guard cd >= 1, cd <= prevLen,
                  let dd = calendar.date(byAdding: .day, value: cd - 1, to: prevStart),
                  let log = logs[dd] else { continue }
            samePointSymptoms.append(contentsOf: log.symptoms)
            if let m = log.mood { samePointMood[m, default: 0] += 1 }
        }

        return PreviousCycleInsight(
            symptomsByPhase: symptomsByPhase,
            moodByPhase: moodByPhase,
            atSamePoint: Array(Set(samePointSymptoms)),
            moodAtSamePoint: samePointMood.max { $0.value < $1.value }?.key,
            sameWindowDescription: "cycle days \(max(1, cd0 - 2))–\(cd0 + 2)"
        )
    }

    /// Assemble everything the recommender needs for one generation.
    func promptContext(on date: Date = Date()) -> PromptContext {
        PromptContext(
            summary: summary(on: date),
            today: day(date),
            lastThreePeriodStarts: lastPeriodStarts(3, onOrBefore: date),
            forecast: upcomingPhases(on: date),
            previous: previousCycleInsight(on: date),
            recent: recentLogs(days: 10, on: date)
        )
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        var logs: [DailyLog]
        var cycleLengthOverride: Int?
        var periodLengthOverride: Int?
        var customSymptoms: [Symptom]?
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else { return }
        guard let decoded = try? JSONDecoder.moonly.decode(Persisted.self, from: data) else { return }
        logs = Dictionary(decoded.logs.map { (day($0.date), $0) }, uniquingKeysWith: { first, _ in first })
        cycleLengthOverride = decoded.cycleLengthOverride
        periodLengthOverride = decoded.periodLengthOverride
        customSymptoms = decoded.customSymptoms ?? []
    }

    private func save() {
        let payload = Persisted(
            logs: logs.values.sorted { $0.date < $1.date },
            cycleLengthOverride: cycleLengthOverride,
            periodLengthOverride: periodLengthOverride,
            customSymptoms: customSymptoms.isEmpty ? nil : customSymptoms
        )
        guard let data = try? JSONEncoder.moonly.encode(payload) else { return }
        try? data.write(to: storeURL, options: .atomic)
    }
}

// MARK: - Small helpers

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension JSONEncoder {
    static var moonly: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }
}

extension JSONDecoder {
    static var moonly: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
