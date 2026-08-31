import PaceCore

/// The seam between AppState and its local Codex session-data source.
protocol UsageSource: AnyObject {
    /// nil = the fetch was skipped (e.g. the sign-in window is up, or a
    /// scrape is already in flight); the caller leaves state untouched.
    /// The API source never returns nil.
    func fetch() async -> Result<UsageSnapshot, FetchStatus>?
}
