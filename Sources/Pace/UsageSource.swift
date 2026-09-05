import PaceCore

/// The seam between AppState and its data source. Exactly one implementation
/// is active per launch: the API source when Claude Code credentials exist
/// in the Keychain, the browser scraper otherwise. Failure carries the same
/// FetchStatus the UI already renders.
protocol UsageSource: AnyObject {
    /// nil = the fetch was skipped (e.g. the sign-in window is up, or a
    /// scrape is already in flight); the caller leaves state untouched.
    /// The API source never returns nil.
    func fetch() async -> Result<UsageSnapshot, FetchStatus>?
}
