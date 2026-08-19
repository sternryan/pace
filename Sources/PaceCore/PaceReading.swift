import Foundation

public struct PaceReading: Equatable, Sendable {
    public let lane: LaneUsage
    public let percentElapsed: Int?
    public let isAheadOfPace: Bool
    public let projectedCapDate: Date?
    /// True when the lane deserves the red treatment: locally ahead of pace,
    /// or the server reports critical/exceeded (the server can see caps the
    /// local pace model can't).
    public let isAlarmed: Bool
    /// For a projected cap: whether the window resets before the cap would
    /// hit — i.e. whether the user actually needs to care. nil when there is
    /// no projection.
    public let capBeforeReset: Bool?

    public init(lane: LaneUsage, percentElapsed: Int?, isAheadOfPace: Bool, projectedCapDate: Date?,
                isAlarmed: Bool = false, capBeforeReset: Bool? = nil) {
        self.lane = lane
        self.percentElapsed = percentElapsed
        self.isAheadOfPace = isAheadOfPace
        self.projectedCapDate = projectedCapDate
        self.isAlarmed = isAlarmed
        self.capBeforeReset = capBeforeReset
    }
}
