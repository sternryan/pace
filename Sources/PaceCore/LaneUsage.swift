import Foundation

public struct LaneUsage: Equatable, Sendable, Codable {
    public let kind: LaneKind
    public let percentUsed: Int
    public let resetDate: Date
    /// Total length of this lane's reset window. `nil` when not yet known —
    /// callers MUST treat `nil` as "can't compute pace for this lane" and
    /// never substitute a guessed duration. See Global Constraints.
    public let windowLength: TimeInterval?
    /// Server-reported severity; `.normal` for sources that don't carry one
    /// (the browser scrape path).
    public let severity: LaneSeverity
    /// Server-provided model label for a scoped lane (e.g. "Fable"). A label
    /// only — lane identity comes from `kind`, so a model rename relabels
    /// the row instead of breaking it.
    public let displayNameOverride: String?

    public init(kind: LaneKind, percentUsed: Int, resetDate: Date, windowLength: TimeInterval?,
                severity: LaneSeverity = .normal, displayNameOverride: String? = nil) {
        self.kind = kind
        self.percentUsed = percentUsed
        self.resetDate = resetDate
        self.windowLength = windowLength
        self.severity = severity
        self.displayNameOverride = displayNameOverride
    }

    public var effectiveDisplayName: String {
        if let displayNameOverride, kind == .fableWeek { return "\(displayNameOverride) · week" }
        return kind.displayName
    }
}
