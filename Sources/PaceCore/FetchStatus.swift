/// Conforms to Error so it can be the Failure type of
/// Result<UsageSnapshot, FetchStatus> at the UsageSource seam.
public enum FetchStatus: Error, Equatable, Sendable {
    case ok
    case needsLogin
    /// API mode: Claude Code credentials exist but the token is expired or
    /// rejected. Distinct from `.needsLogin` (browser mode's claude.ai
    /// sign-in) because the remediation is different — the fix is to open
    /// Claude Code and run /login, and showing a claude.ai sign-in window
    /// here would be the wrong instruction.
    case tokenExpired
    /// Network unreachable, timeout, or a 5xx — retryable, and distinct from
    /// `.parseError`: wifi dropping must not be reported as "the endpoint
    /// shape changed", which is the signal this design specifically watches.
    case transient(String)
    /// The scrape click-through broke for a reason OTHER than being signed
    /// out (e.g. claude.ai renamed a button). Kept separate so the dropdown
    /// never tells you to sign in when you already are.
    case navigationFailed(String)
    case parseError(String)
}
