public enum FetchStatus: Equatable, Sendable {
    case ok
    case needsLogin
    /// Distinct from `.needsLogin`: the click-through navigation broke for a
    /// reason OTHER than being signed out (e.g. claude.ai renamed a button).
    /// Kept separate so the dropdown never tells you to sign in when you
    /// already are — see Task 8's review finding.
    case navigationFailed(String)
    case parseError(String)
}
