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
        !matchingItemRefs().isEmpty
    }

    /// Two passes, deliberately. kSecAttrService has no prefix query, so
    /// discovery must scan — but scanning with kSecReturnData is off the
    /// table twice over: macOS rejects kSecMatchLimitAll combined with
    /// kSecReturnData outright (errSecParam -50, verified on macOS 15 — batch
    /// decryption is not a thing), and even per-item it would touch secrets
    /// Pace has no business reading. Pass 1 requests attributes only (no
    /// decryption, no prompts) to find the matching (service, account) pairs;
    /// pass 2 reads each matched item INDIVIDUALLY with kSecMatchLimitOne —
    /// the only form the API decrypts — so macOS prompts about the Claude
    /// Code items and nothing else. Pinning account as well as service is
    /// what keeps the duplicate-service trap closed: limit-one by service
    /// alone would return the first (possibly stale) item.
    private func matchingItemRefs() -> [(service: String, account: String)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        var refs: [(String, String)] = []
        for item in items {
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix(Self.servicePrefix),
                  let account = item[kSecAttrAccount as String] as? String else { continue }
            let key = "\(service)\u{0}\(account)"
            if seen.insert(key).inserted { refs.append((service, account)) }
        }
        return refs
    }

    private func copyAllMatchingItemPayloads() -> [Data] {
        matchingItemRefs().compactMap { ref in
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: ref.service,
                kSecAttrAccount as String: ref.account,
                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true
            ]
            var result: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
            return result as? Data
        }
    }
}
