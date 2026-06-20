import SwiftUI

/// The four phases of a typical menstrual cycle. Boundaries are derived per
/// user from their own averaged cycle/period length rather than hard-coded to
/// a 28-day textbook cycle.
enum CyclePhase: String, Codable, CaseIterable, Identifiable {
    case menstrual
    case follicular
    case ovulatory
    case luteal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .menstrual:  return "Menstrual"
        case .follicular: return "Follicular"
        case .ovulatory:  return "Ovulatory"
        case .luteal:     return "Luteal"
        }
    }

    /// A short, plain-language description of what is typically happening.
    var blurb: String {
        switch self {
        case .menstrual:
            return "Hormones are at their lowest. Bleeding, cramps and fatigue are common."
        case .follicular:
            return "Estrogen is rising. Energy, mood and focus usually climb with it."
        case .ovulatory:
            return "Estrogen peaks and an egg is released. Energy and libido often peak too."
        case .luteal:
            return "Progesterone rises then falls. PMS, cravings and lower energy may appear."
        }
    }

    var systemImage: String {
        switch self {
        case .menstrual:  return "drop.fill"
        case .follicular: return "leaf.fill"
        case .ovulatory:  return "sparkles"
        case .luteal:     return "moon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .menstrual:  return Color(red: 0.84, green: 0.31, blue: 0.40)
        case .follicular: return Color(red: 0.36, green: 0.66, blue: 0.51)
        case .ovulatory:  return Color(red: 0.92, green: 0.69, blue: 0.27)
        case .luteal:     return Color(red: 0.47, green: 0.46, blue: 0.78)
        }
    }
}
