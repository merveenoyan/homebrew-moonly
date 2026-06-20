import Foundation

/// A loggable physical symptom. Includes both built-in and user-defined symptoms.
struct Symptom: Codable, Hashable, Identifiable {
    let rawValue: String
    var id: String { rawValue }

    /// Built-in symptoms.
    static let cramps = Symptom(rawValue: "cramps")
    static let headache = Symptom(rawValue: "headache")
    static let bloating = Symptom(rawValue: "bloating")
    static let backache = Symptom(rawValue: "backache")
    static let breastTenderness = Symptom(rawValue: "breastTenderness")
    static let acne = Symptom(rawValue: "acne")
    static let nausea = Symptom(rawValue: "nausea")
    static let fatigue = Symptom(rawValue: "fatigue")
    static let insomnia = Symptom(rawValue: "insomnia")
    static let cravings = Symptom(rawValue: "cravings")
    static let dizziness = Symptom(rawValue: "dizziness")
    static let digestive = Symptom(rawValue: "digestive")

    static let builtIn: [Symptom] = [
        .cramps, .headache, .bloating, .backache, .breastTenderness, .acne,
        .nausea, .fatigue, .insomnia, .cravings, .dizziness, .digestive
    ]

    /// Create a user-defined custom symptom.
    static func custom(_ name: String) -> Symptom {
        Symptom(rawValue: "custom:\(name)")
    }

    var isCustom: Bool { rawValue.hasPrefix("custom:") }

    var label: String {
        if isCustom {
            return String(rawValue.dropFirst("custom:".count))
        }
        switch rawValue {
        case "cramps":           return "Cramps"
        case "headache":         return "Headache"
        case "bloating":         return "Bloating"
        case "backache":         return "Backache"
        case "breastTenderness": return "Tenderness"
        case "acne":             return "Acne"
        case "nausea":           return "Nausea"
        case "fatigue":          return "Fatigue"
        case "insomnia":         return "Insomnia"
        case "cravings":         return "Cravings"
        case "dizziness":        return "Dizziness"
        case "digestive":        return "Digestive"
        default:                 return rawValue.capitalized
        }
    }

    var emoji: String {
        if isCustom { return "🏷️" }
        switch rawValue {
        case "cramps":           return "🤕"
        case "headache":         return "🤯"
        case "bloating":         return "🎈"
        case "backache":         return "🪨"
        case "breastTenderness": return "💢"
        case "acne":             return "🔴"
        case "nausea":           return "🤢"
        case "fatigue":          return "🥱"
        case "insomnia":         return "🌙"
        case "cravings":         return "🍫"
        case "dizziness":        return "😵‍💫"
        case "digestive":        return "🌀"
        default:                 return "🏷️"
        }
    }
}

/// Bleeding intensity for a given day.
enum Flow: String, Codable, CaseIterable, Identifiable {
    case spotting, light, medium, heavy

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var dots: Int {
        switch self {
        case .spotting: return 1
        case .light:    return 2
        case .medium:   return 3
        case .heavy:    return 4
        }
    }
}

/// Coarse self-reported mood.
enum Mood: String, Codable, CaseIterable, Identifiable {
    case great, good, neutral, irritable, anxious, low

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var emoji: String {
        switch self {
        case .great:     return "😄"
        case .good:      return "🙂"
        case .neutral:   return "😐"
        case .irritable: return "😤"
        case .anxious:   return "😟"
        case .low:       return "😔"
        }
    }
}

/// Coarse self-reported energy level.
enum Energy: String, Codable, CaseIterable, Identifiable {
    case high, medium, low

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var emoji: String {
        switch self {
        case .high:   return "⚡️"
        case .medium: return "🔋"
        case .low:    return "🪫"
        }
    }
}
