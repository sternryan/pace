import Foundation

public struct LaneUsage: Equatable, Sendable {
    public let kind: LaneKind
    public let percentUsed: Int
    public let resetDate: Date
    /// Total length of this lane's reset window. `nil` when not yet known —
    /// callers MUST treat `nil` as "can't compute pace for this lane" and
    /// never substitute a guessed duration. See Global Constraints.
    public let windowLength: TimeInterval?

    public init(kind: LaneKind, percentUsed: Int, resetDate: Date, windowLength: TimeInterval?) {
        self.kind = kind
        self.percentUsed = percentUsed
        self.resetDate = resetDate
        self.windowLength = windowLength
    }
}
