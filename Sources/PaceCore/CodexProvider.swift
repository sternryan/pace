import Foundation

public final class CodexProvider: Provider, @unchecked Sendable {
    public let id: ProviderID = .codex
    private let authStore: CodexAuthStore
    private let client: CodexUsageClient
    private let sessions: CodexSessionUsageSource
    private var lastGood: [LaneUsage] = []
    /// A token this provider refreshed itself, held only in memory. Pace
    /// never writes `~/.codex/auth.json` — the Codex CLI owns renewal and
    /// token persistence — but a mid-session refresh still needs somewhere
    /// to live so the next poll doesn't immediately refresh again.
    private var refreshedAuth: CodexAuth?

    public init(authStore: CodexAuthStore = CodexAuthStore(), client: CodexUsageClient = CodexUsageClient(),
                sessions: CodexSessionUsageSource = CodexSessionUsageSource()) {
        self.authStore = authStore; self.client = client; self.sessions = sessions
    }

    public func fetch(now: Date) async -> ProviderSnapshot {
        guard var auth = refreshedAuth ?? authStore.load() else {
            return fallback(now: now, error: .needsLogin("run `codex login`"))
        }
        if CodexAuthStore.needsRefresh(auth, now: now), let fresh = await client.refresh(auth: auth, now: now) {
            auth = fresh; refreshedAuth = fresh
        }
        switch await client.fetchUsage(auth: auth) {
        case .success(let data):
            guard let lanes = CodexUsageNormalizer.lanes(fromJSON: data, now: now) else {
                return fallback(now: now, error: .parseError("wham/usage shape changed"))
            }
            lastGood = lanes
            return ProviderSnapshot(provider: .codex, fetchedAt: now, source: .api, lanes: lanes)
        case .failure(.unauthorized):
            return fallback(now: now, error: .needsLogin("run `codex login`"))
        case .failure(let f):
            return fallback(now: now, error: .transient("\(f)"))
        }
    }

    private func fallback(now: Date, error: ProviderError) -> ProviderSnapshot {
        if let lanes = sessions.latestLanes(now: now) {
            return ProviderSnapshot(provider: .codex, fetchedAt: now, source: .localFallback, lanes: lanes, error: error)
        }
        return ProviderSnapshot(provider: .codex, fetchedAt: now, source: .cache, lanes: lastGood, error: error)
    }
}
