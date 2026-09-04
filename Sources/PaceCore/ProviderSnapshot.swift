import Foundation

public enum ProviderID: String, Codable, Sendable, CaseIterable { case claude, codex, smithy, spend }

public enum SnapshotSource: String, Codable, Sendable { case api, localFallback, cache }

/// Three states, never two (memory infra_silent_false_negative_lanes).
public enum LaneState: String, Codable, Sendable, CaseIterable { case serving, leasedAway, unreachable }

public enum ProviderError: Error, Equatable, Codable, Sendable {
    case needsLogin(String)       // human instruction, e.g. "open Claude Code"
    case transient(String)
    case parseError(String)
    case unreachable(String)

    public var message: String {
        switch self {
        case .needsLogin(let s), .transient(let s), .parseError(let s), .unreachable(let s): return s
        }
    }
}

public struct ProviderSnapshot: Equatable, Codable, Sendable {
    public let provider: ProviderID
    public let fetchedAt: Date
    public let source: SnapshotSource
    public let lanes: [LaneUsage]
    public let laneState: LaneState?
    public let burn: BurnSeries?
    public let error: ProviderError?

    public init(provider: ProviderID, fetchedAt: Date, source: SnapshotSource, lanes: [LaneUsage],
                laneState: LaneState? = nil, burn: BurnSeries? = nil, error: ProviderError? = nil) {
        self.provider = provider; self.fetchedAt = fetchedAt; self.source = source
        self.lanes = lanes; self.laneState = laneState; self.burn = burn; self.error = error
    }
}

public protocol Provider: Sendable {
    var id: ProviderID { get }
    /// Never throws. Failures are reported inside the snapshot with `error` set
    /// and whatever lanes could still be produced (possibly from cache).
    func fetch(now: Date) async -> ProviderSnapshot
}
