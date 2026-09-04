// Local shim (NOT vendored from openusage) — see Sources/PaceCore/Vendor/VENDORED.md.
import Foundation

/// Local stand-in for upstream's `EnvironmentReading`/`ProcessEnvironmentReader` pair
/// (`Sources/OpenUsage/Services/SystemClients.swift`). The upstream implementation also
/// consults a captured login-shell environment (`LoginShellEnvironment`,
/// `ShellEnvironmentSnapshotStore`) so a packaged app launched from Finder still sees a
/// user's shell-profile exports; that snapshot machinery is app-lifecycle/telemetry-adjacent
/// and out of scope for PaceCore, so this reads only `ProcessInfo.processInfo.environment`.
/// PaceCore's callers (log scanners honoring `CLAUDE_CONFIG_DIR` / `CODEX_HOME`) only need a
/// same-process environment read, which this provides in full.
protocol EnvironmentReading: Sendable {
    func value(for name: String) -> String?
}

struct ProcessEnvironmentReader: EnvironmentReading {
    var processEnvironment: [String: String] = ProcessInfo.processInfo.environment

    func value(for name: String) -> String? {
        let value = processEnvironment[name]
        return (value?.isEmpty ?? true) ? nil : value
    }
}

/// Expands a leading `~` to the current user's home directory. Vendored verbatim from
/// `Sources/OpenUsage/Services/SystemClients.swift`.
func expandHome(_ path: String) -> String {
    guard path == "~" || path.hasPrefix("~/") else { return path }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    if path == "~" { return home }
    return home + String(path.dropFirst())
}
