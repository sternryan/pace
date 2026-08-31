public enum LaneKind: String, CaseIterable, Hashable, Sendable, Codable {
    case primary
    case secondary
    // Retained for source compatibility with PaceCore's historical parsers.
    case session
    case allModelsWeek
    case fableWeek

    public var displayName: String {
        switch self {
        case .primary: return "Primary window"
        case .secondary: return "Secondary window"
        case .session: return "Current session"
        case .allModelsWeek: return "All models · week"
        case .fableWeek: return "Fable · week"
        }
    }
}
