import Foundation

public enum ProjectionBasis: String, Codable, Sendable { case burnRate, percentRate, none }

public struct WindowVerdict: Equatable, Codable, Sendable {
    public let kind: LaneKind
    public let provider: ProviderID
    public let percentUsed: Int
    public let percentElapsed: Int?
    public let resetsAt: Date
    public let status: PaceStatus
    public let projectedCapAt: Date?      // nil when resetsFirst, tooEarly, or no rate
    public let resetsFirst: Bool
    public let projectionBasis: ProjectionBasis
    /// Carried through from `LaneUsage.severity` so a viewer can see the
    /// server-asserted alarm even after it has already been folded into
    /// `status` (see `PacingEngine.verdict`'s severity-promotion rule).
    public let severity: LaneSeverity
    public let source: SnapshotSource
    public let fetchedAt: Date
    public let verdict: String
}

public struct ProviderStatus: Equatable, Codable, Sendable {
    public let provider: ProviderID
    public let source: SnapshotSource
    public let fetchedAt: Date
    public let error: String?
}

public struct PaceReport: Equatable, Codable, Sendable {
    public let generatedAt: Date
    public let headline: WindowVerdict?
    public let advice: String?
    public let windows: [WindowVerdict]
    public let laneState: LaneState?
    public let burn: BurnSeries?
    public let providers: [ProviderStatus]
    public let stale: Bool
}
