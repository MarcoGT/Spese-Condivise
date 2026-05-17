import SwiftUI

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case food          = "food"
    case transport     = "transport"
    case accommodation = "accommodation"
    case entertainment = "entertainment"
    case shopping      = "shopping"
    case health        = "health"
    case utilities     = "utilities"
    case other         = "other"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .food:          return "fork.knife"
        case .transport:     return "car.fill"
        case .accommodation: return "house.fill"
        case .entertainment: return "ticket.fill"
        case .shopping:      return "cart.fill"
        case .health:        return "cross.fill"
        case .utilities:     return "bolt.fill"
        case .other:         return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .food:          return .orange
        case .transport:     return .blue
        case .accommodation: return .teal
        case .entertainment: return .purple
        case .shopping:      return .pink
        case .health:        return .red
        case .utilities:     return .yellow
        case .other:         return .secondary
        }
    }

    var localizedName: String {
        NSLocalizedString("category_\(rawValue)", comment: "")
    }

    // Inizializza da stringa salvata, fallback su .other
    static func from(_ string: String?) -> ExpenseCategory {
        guard let string else { return .other }
        return ExpenseCategory(rawValue: string) ?? .other
    }
}
