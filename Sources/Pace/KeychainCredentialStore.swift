import Foundation
import Security
import os
import PaceCore

enum KeychainReadResult {
    case found(ClaudeCodeCredential)
    /// Items exist but every credential is expired — the user has Claude Code
    /// and needs to re-login there. NOT the same as `.none`: showing a
    /// claude.ai sign-in window here would be the wrong remediation.
    case allExpired
    case none
}

/// Reads Claude Code's OAuth credentials. Discovery is native
/// (SecItemCopyMatching, attributes only); the DECRYPT goes through
/// /usr/bin/security, on purpose: Claude Code writes its item with
/// `security add-generic-password -U`, so `security` is already on that
/// item's ACL — reading through it never prompts. A Pace-scoped grant
/// (SecItemCopyMatching with kSecReturnData) is the opposite: every `claude`
/// launch rewrites the item and wipes the grant, so the "Always Allow" the
/// user clicked is gone by the next poll. Verified 2026-08-21: the shell
/// read returns the live item with zero prompt. Shelling out extends no
/// access — the ACL entry for `security` exists whether Pace uses it or not.
/// Multiple items can share the service name (and suffixed variants exist),
/// so this enumerates ALL matching items and lets
/// ClaudeCodeCredential.selectFreshest pick — a single-match read was
/// observed returning a stale token right after a successful login.
///
/// Class, not struct: needs to remember which items recently required (and
/// didn't get) user interaction, across polls.
final class KeychainCredentialStore {
    private static let servicePrefix = "Claude Code-credentials"
    /// Every `claude` CLI launch rewrites its credential item (confirmed:
    /// item mdat lines up with a `claude` process start time), and rewriting
    /// resets that item's Keychain ACL grant — so the item Pace most wants
    /// (newest) is also the one most likely to need a fresh interactive
    /// prompt. Without a cooldown, a poll every `refreshInterval` (120s in
    /// API mode) re-prompts on that same item every single tick, which reads
    /// as Pace "asking over and over" even though the user just hasn't
    /// clicked Always Allow yet. Back off and fall through to the last item
    /// that decrypted cleanly instead.
    private static let promptCooldown: TimeInterval = 20 * 60
    private var lastPromptFailure: [String: Date] = [:]
    private static let log = Logger(subsystem: "com.sternryan.pace", category: "keychain")

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
            let key = itemKey(ref)
            if let failedAt = lastPromptFailure[key], now.timeIntervalSince(failedAt) < Self.promptCooldown {
                continue // still cooling down — don't re-prompt, try the next-best item
            }
            let (data, status) = copyItemPayload(for: ref)
            guard let data else {
                if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed {
                    Self.log.notice("keychain prompt not granted for \(ref.account, privacy: .public) (status \(status, privacy: .public)) — backing off \(Int(Self.promptCooldown / 60), privacy: .public)m")
                    lastPromptFailure[key] = now
                }
                continue
            }
            lastPromptFailure.removeValue(forKey: key)
            guard let credential = ClaudeCodeCredential.parse(itemData: data) else { continue }
            parsedAny = true
            if credential.expiresAt.map({ $0 > now }) ?? true {
                return .found(credential)
            }
        }
        // No items, or items exist but none parse — both currently map to
        // the same remediation; don't build a future mode decision on .none alone.
        return parsedAny ? .allExpired : .none
    }

    private func itemKey(_ ref: (service: String, account: String, modified: Date)) -> String {
        "\(ref.service)\u{0}\(ref.account)"
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

    private func copyItemPayload(for ref: (service: String, account: String, modified: Date)) -> (data: Data?, status: OSStatus) {
        if let data = readViaSecurityCLI(service: ref.service, account: ref.account) {
            return (data, errSecSuccess)
        }
        // Fallback: native read. This one CAN prompt (and the cooldown in
        // `read` governs it) — only reached if /usr/bin/security failed.
        return copyItemPayloadNative(for: ref)
    }

    /// `security find-generic-password -w` prints the secret as text (hex if
    /// it isn't valid text — not the case for Claude Code's JSON) followed by
    /// a newline. Nonzero exit / empty output → nil so the caller falls back.
    private func readViaSecurityCLI(service: String, account: String) -> Data? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        proc.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = FileHandle.nullDevice
        do { try proc.run() } catch {
            Self.log.error("security CLI launch failed: \(String(describing: error), privacy: .public)")
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            Self.log.notice("security CLI exit \(proc.terminationStatus, privacy: .public) for \(account, privacy: .public) — falling back to native read")
            return nil
        }
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        while text.hasSuffix("\n") || text.hasSuffix("\r") { text.removeLast() }
        return text.isEmpty ? nil : Data(text.utf8)
    }

    private func copyItemPayloadNative(for ref: (service: String, account: String, modified: Date)) -> (data: Data?, status: OSStatus) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: ref.service,
            kSecAttrAccount as String: ref.account,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return (nil, status) }
        return (result as? Data, status)
    }
}
