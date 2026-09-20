public enum LaneKind: String, CaseIterable, Hashable, Sendable, Codable {
    case session
    case allModelsWeek
    case fableWeek
    // Codex reports its own windows rather than named plans; the source supplies
    // the label via displayNameOverride and lane identity stays stable when Codex
    // changes which windows a plan exposes.
    case primary
    case secondary

    public var displayName: String {
        switch self {
        case .session: return "Current session"
        case .allModelsWeek: return "All models · week"
        case .fableWeek: return "Fable · week"
        case .primary: return "Primary window"
        case .secondary: return "Secondary window"
        }
    }
}
