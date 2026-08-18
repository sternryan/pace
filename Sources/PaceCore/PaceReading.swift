import Foundation

public struct PaceReading: Equatable, Sendable {
    public let lane: LaneUsage
    public let percentElapsed: Int?
    public let isAheadOfPace: Bool
    public let projectedCapDate: Date?

    public init(lane: LaneUsage, percentElapsed: Int?, isAheadOfPace: Bool, projectedCapDate: Date?) {
        self.lane = lane
        self.percentElapsed = percentElapsed
        self.isAheadOfPace = isAheadOfPace
        self.projectedCapDate = projectedCapDate
    }
}
