public enum LaneKind: String, CaseIterable, Hashable, Sendable {
    case session
    case allModelsWeek
    case fableWeek

    public var displayName: String {
        switch self {
        case .session: return "Current session"
        case .allModelsWeek: return "All models · week"
        case .fableWeek: return "Fable · week"
        }
    }
}
