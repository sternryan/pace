import Foundation

public protocol ClaudeUsageFetching: Sendable { func fetch() async -> Result<UsageSnapshot, FetchStatus>? }
extension ApiUsageSource: ClaudeUsageFetching {}

public final class ClaudeProvider: Provider, @unchecked Sendable {
    public let id: ProviderID = .claude
    private let source: ClaudeUsageFetching
    private var lastGood: [LaneUsage] = []
    public init(source: ClaudeUsageFetching = ApiUsageSource()) { self.source = source }

    public func fetch(now: Date) async -> ProviderSnapshot {
        switch await source.fetch() {
        case .success(let snap)?:
            var lanes = snap.lanes
            if let x = snap.extraUsage, x.isEnabled {
                lanes.append(LaneUsage(kind: .overage, percentUsed: Int(x.dollarsUsed), resetDate: .distantFuture, windowLength: nil))
            }
            lastGood = lanes
            return ProviderSnapshot(provider: .claude, fetchedAt: now, source: .api, lanes: lanes)
        case .failure(.tokenExpired)?, .failure(.needsLogin)?:
            return ProviderSnapshot(provider: .claude, fetchedAt: now, source: .cache, lanes: lastGood, error: .needsLogin("open Claude Code to refresh sign-in"))
        case .failure(let f)?:
            return ProviderSnapshot(provider: .claude, fetchedAt: now, source: .cache, lanes: lastGood, error: .transient("\(f)"))
        case nil:
            return ProviderSnapshot(provider: .claude, fetchedAt: now, source: .cache, lanes: lastGood, error: .transient("no fetch"))
        }
    }
}
