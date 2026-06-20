import SwiftUI

/// A compact two-week strip for context: phase color per day, a drop on period
/// days, and a marker when symptoms were logged.
struct HistoryView: View {
    @EnvironmentObject var store: CycleStore
    let endDate: Date
    var days: Int = 14

    private let cal = Calendar.current
    private static let wd: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "EEEEE"; return f   // single-letter weekday
    }()

    private var dates: [Date] {
        (0..<days).reversed().map { offset in
            cal.startOfDay(for: cal.date(byAdding: .day, value: -offset, to: endDate)!)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Last \(days) days")
            HStack(spacing: 4) {
                ForEach(dates, id: \.self) { date in
                    let log = store.log(on: date)
                    let phase = store.cycleDay(on: date).map { store.phase(forCycleDay: $0) }
                    VStack(spacing: 3) {
                        Text(Self.wd.string(from: date))
                            .font(.system(size: 8)).foregroundStyle(.tertiary)
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill((phase?.tint ?? .gray).opacity(log.isPeriod ? 0.9 : 0.18))
                            if !log.symptoms.isEmpty && !log.isPeriod {
                                Circle().fill(.secondary).frame(width: 3, height: 3)
                            }
                        }
                        .frame(height: 18)
                        Text("\(cal.component(.day, from: date))")
                            .font(.system(size: 8)).monospacedDigit()
                            .foregroundStyle(cal.isDate(date, inSameDayAs: endDate) ? .primary : .tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
