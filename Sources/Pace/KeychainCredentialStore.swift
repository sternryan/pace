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
        // Decrypt newest-modified item first and stop as soon as one parses
        // non-expired — each candidate is a SEPARATE Keychain item with its
        // own ACL grant, so decrypting all of them on every poll means every
        // duplicate/stale item (e.g. a leftover suffixed variant from another
        // Claude Code install) re-prompts the user on its own schedule. Modification
        // date is available from the attributes-only pass (no decrypt, no
        // prompt), and correlates with token freshness closely enough to use
        // as a decrypt order — correctness still comes from expiresAt below,
        // this just changes which item we reach for first.
        var parsedAny = false
        for ref in matchingItemRefsSortedByRecency() {
            guard let data = copyItemPayload(for: ref),
                  let credential = ClaudeCodeCredential.parse(itemData: data) else { continue }
            parsedAny = true
            if credential.expiresAt.map({ $0 > now }) ?? true {
                return .found(credential)
            }
        }
        // No items, or items exist but none parse — both currently map to
        // the same remediation; don't build a future mode decision on .none alone.
        return parsedAny ? .allExpired : .none
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
        matchingItemRefsSortedByRecency().map { ($0.service, $0.account) }
    }

    /// Same pass-1 scan, but also pulls kSecAttrModificationDate (still
    /// attributes-only — free) and sorts newest-first so `read` decrypts the
    /// item Claude Code is actively touching before any stale duplicates.
    private func matchingItemRefsSortedByRecency() -> [(service: String, account: String, modified: Date)] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        var seen = Set<String>()
        var refs: [(service: String, account: String, modified: Date)] = []
        for item in items {
            guard let service = item[kSecAttrService as String] as? String,
                  service.hasPrefix(Self.servicePrefix),
                  let account = item[kSecAttrAccount as String] as? String else { continue }
            let key = "\(service)\u{0}\(account)"
            guard seen.insert(key).inserted else { continue }
            let modified = (item[kSecAttrModificationDate as String] as? Date) ?? .distantPast
            refs.append((service, account, modified))
        }
        return refs.sorted { $0.modified > $1.modified }
    }

    private func copyItemPayload(for ref: (service: String, account: String, modified: Date)) -> Data? {
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
