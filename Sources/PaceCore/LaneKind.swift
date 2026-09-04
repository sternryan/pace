public enum LaneKind: String, CaseIterable, Hashable, Sendable, Codable {
    case session
    case allModelsWeek
    case fableWeek
    case overage
    case codexSession
    case codexWeek

    public var displayName: String {
        switch self {
        case .session: return "Current session"
        case .allModelsWeek: return "All models · week"
        case .fableWeek: return "Fable · week"
        case .overage: return "Extra usage"
        case .codexSession: return "Codex 5h"
        case .codexWeek: return "Codex · week"
        }
    }

    public var provider: ProviderID {
        switch self {
        case .session, .allModelsWeek, .fableWeek, .overage: return .claude
        case .codexSession, .codexWeek: return .codex
        }
    }
}
