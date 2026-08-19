/// Server-reported severity for a usage lane. The endpoint is undocumented,
/// so unknown values degrade to `.normal` rather than failing the whole parse.
public enum LaneSeverity: String, Equatable, Sendable, Codable, CaseIterable {
    case normal, warning, critical, exceeded

    public init(rawServerValue: String?) {
        self = rawServerValue.flatMap(LaneSeverity.init(rawValue:)) ?? .normal
    }

    /// Whether the server considers this lane in an alarm state. Server
    /// severity can force the alarm even when local pace math wouldn't —
    /// the server knows about caps the pace model can't see.
    public var isAlarming: Bool { self == .critical || self == .exceeded }
}
