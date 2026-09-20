import Foundation

/// The two usage sources Pace tracks. Each gets its OWN menubar icon and its own
/// cache; they are never collapsed into one verdict.
///
/// pace v3 (2026-09-05) merged these into a single headline window and was
/// reverted the same day -- "consolidation traded scanability for cleverness"
/// (docs/NOTES-2026-09-05-v3-revert.md). Two glanceable icons is the product
/// requirement this type exists to keep honest.
public enum PaceProvider: String, CaseIterable, Hashable, Sendable, Codable {
    case claude
    case codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }
}
