import Foundation
import PaceCore

/// Primary data source: the same endpoint Claude Code's /usage command reads.
/// One GET per refresh; the token is used in-memory only — never stored,
/// never logged, never refreshed (Claude Code owns renewal).
final class ApiUsageSource: UsageSource {
    private static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private let store: KeychainCredentialStore
    private let session: URLSession

    init(store: KeychainCredentialStore = KeychainCredentialStore()) {
        self.store = store
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10 // a hung socket must not wedge the refresh cycle
        self.session = URLSession(configuration: config)
    }

    func fetch() async -> Result<UsageSnapshot, FetchStatus>? {
        let credential: ClaudeCodeCredential
        switch store.read() {
        case .found(let found): credential = found
        case .allExpired, .none:
            // .none shouldn't occur in API mode (mode selection saw an item)
            // but a user can delete the item mid-session; either way the
            // remediation is Claude Code's login, not claude.ai's.
            return .failure(.tokenExpired)
        }

        var request = URLRequest(url: Self.usageURL)
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            return .failure(.transient("network unreachable"))
        }

        guard let http = response as? HTTPURLResponse else {
            return .failure(.transient("unexpected response"))
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            // Expiry math said the token was fresh but the server disagrees
            // (revoked, or clock skew) — the server is the authority.
            return .failure(.tokenExpired)
        }
        guard (200..<300).contains(http.statusCode) else {
            // 5xx and friends are retryable server trouble, NOT shape churn —
            // .parseError is reserved for "the endpoint changed", the signal
            // this design specifically watches for.
            return .failure(.transient("usage request failed (HTTP \(http.statusCode))"))
        }

        guard let snapshot = ApiUsageNormalizer.snapshot(fromJSON: data, now: Date()) else {
            return .failure(.parseError("usage endpoint shape changed"))
        }
        return .success(snapshot)
    }
}
