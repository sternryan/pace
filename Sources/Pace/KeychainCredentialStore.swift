import Foundation
import Security
import PaceCore

enum KeychainReadResult {
    case found(ClaudeCodeCredential)
    /// Items exist but every credential is expired — the user has Claude Code
    /// and needs to re-login there. NOT the same as `.none`: showing a
    /// claude.ai sign-in window here would be the wrong remediation.
    case allExpired
    case none
}

/// Reads Claude Code's OAuth credentials natively (SecItemCopyMatching), so
/// the user's Keychain grant is scoped to Pace.app itself — shelling out to
/// /usr/bin/security would extend the grant to every CLI process on the
/// machine. Multiple items can share the service name (and suffixed
/// variants exist), so this enumerates ALL matching items and lets
/// ClaudeCodeCredential.selectFreshest pick — a single-match read was
/// observed returning a stale token right after a successful login.
struct KeychainCredentialStore {
    private static let servicePrefix = "Claude Code-credentials"

    func read(now: Date = Date()) -> KeychainReadResult {
        let payloads = copyAllMatchingItemPayloads()
        guard !payloads.isEmpty else { return .none }
        let credentials = payloads.compactMap(ClaudeCodeCredential.parse(itemData:))
        // Items that exist but don't parse also return .none — this conflates
        // "no Claude Code" with "unreadable items". Both currently map to the
        // same remediation; don't build a future mode decision on .none alone.
        guard !credentials.isEmpty else { return .none }
        if let freshest = ClaudeCodeCredential.selectFreshest(from: credentials, now: now) {
            return .found(freshest)
        }
        return .allExpired
    }

    /// Attributes-only (pass 1): costs nothing, decrypts nothing, prompts for
    /// nothing — safe to call synchronously at launch for mode selection.
    func hasAnyItem() -> Bool {
        !matchingServiceNames().isEmpty
    }

    /// Two passes, deliberately. kSecAttrService has no prefix query, so
    /// discovery must scan — but a single scan with kSecReturnData would ask
    /// the Keychain to DECRYPT every generic password on the machine (hundreds
    /// of items), raising one authorization prompt per item Pace isn't
    /// granted. Pass 1 requests attributes only (no decryption, no prompts)
    /// to find the matching service names; pass 2 requests data for exactly
    /// those services, so macOS prompts about the Claude Code item and
    /// nothing else.
    private func matchingServiceNames() -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        let services = items.compactMap { $0[kSecAttrService as String] as? String }
            .filter { $0.hasPrefix(Self.servicePrefix) }
        return Array(Set(services))
    }

    private func copyAllMatchingItemPayloads() -> [Data] {
        matchingServiceNames().flatMap { service -> [Data] in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecMatchLimit as String: kSecMatchLimitAll,
                kSecReturnAttributes as String: true,
                kSecReturnData as String: true
            ]
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let items = result as? [[String: Any]] else { return [] }
            return items.compactMap { $0[kSecValueData as String] as? Data }
        }
    }
}
