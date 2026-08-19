import Foundation

/// A parsed Claude Code OAuth credential. Pace only ever READS these —
/// renewal belongs to Claude Code; refreshing from a second process would
/// rotate a token the owner can't see.
public struct ClaudeCodeCredential: Equatable, Sendable {
    public let accessToken: String
    public let expiresAt: Date?

    public init(accessToken: String, expiresAt: Date?) {
        self.accessToken = accessToken
        self.expiresAt = expiresAt
    }

    /// Parses one Keychain item's payload. Claude Code writes
    /// {"claudeAiOauth": {accessToken, expiresAt(ms), ...}}; a flat object
    /// is accepted for resilience. Returns nil rather than guessing.
    public static func parse(itemData: Data) -> ClaudeCodeCredential? {
        guard let root = (try? JSONSerialization.jsonObject(with: itemData)) as? [String: Any] else { return nil }
        let payload = (root["claudeAiOauth"] as? [String: Any]) ?? root
        guard let token = payload["accessToken"] as? String, !token.isEmpty else { return nil }
        let expiresAt = (payload["expiresAt"] as? NSNumber).map {
            Date(timeIntervalSince1970: $0.doubleValue / 1000) // epoch milliseconds
        }
        return ClaudeCodeCredential(accessToken: token, expiresAt: expiresAt)
    }

    /// Multiple Keychain items can share the Claude Code service name
    /// (different accounts, suffixed variants from other installs). A
    /// single-match read can return a stale item and report the login as
    /// revoked forever — observed live. Pick the latest non-expired
    /// credential; a credential without an expiry is usable but least
    /// preferred (no evidence of freshness).
    public static func selectFreshest(from candidates: [ClaudeCodeCredential], now: Date) -> ClaudeCodeCredential? {
        let usable = candidates.filter { $0.expiresAt.map { $0 > now } ?? true }
        return usable.max { lhs, rhs in
            (lhs.expiresAt ?? .distantPast) < (rhs.expiresAt ?? .distantPast)
        }
    }
}
