import Foundation

public enum PaceCalculator {
    /// No ahead-of-pace verdict (and no projection) until the window holds
    /// this much history — a burst in the first minutes of a fresh window
    /// says nothing about sustained pace and flashed the icon red in v1.
    public static let minimumElapsedForVerdict: TimeInterval = 10 * 60

    public static func reading(for lane: LaneUsage, now: Date) -> PaceReading {
        guard let windowLength = lane.windowLength, windowLength > 0 else {
            return PaceReading(lane: lane, percentElapsed: nil, isAheadOfPace: false,
                               projectedCapDate: nil, isAlarmed: lane.severity.isAlarming,
                               capBeforeReset: nil)
        }

        let windowStart = lane.resetDate.addingTimeInterval(-windowLength)
        let elapsed = max(0, min(now.timeIntervalSince(windowStart), windowLength))
        let percentElapsed = Int((elapsed / windowLength) * 100)
        let ahead = elapsed >= minimumElapsedForVerdict && lane.percentUsed > percentElapsed

        // Projection is decoupled from the ahead verdict: an ahead-of-pace
        // lane's cap always lands before the reset (that's what ahead means),
        // so the "(resets first)" answer — the calming one — can only come
        // from a behind-pace lane. Both need the projection.
        var projectedCapDate: Date? = nil
        var capBeforeReset: Bool? = nil
        if elapsed >= minimumElapsedForVerdict, lane.percentUsed > 0 {
            let ratePerSecond = Double(lane.percentUsed) / elapsed
            let secondsTo100 = 100.0 / ratePerSecond
            let cap = windowStart.addingTimeInterval(secondsTo100)
            projectedCapDate = cap
            capBeforeReset = cap < lane.resetDate
        }

        return PaceReading(lane: lane, percentElapsed: percentElapsed, isAheadOfPace: ahead,
                           projectedCapDate: projectedCapDate,
                           isAlarmed: ahead || lane.severity.isAlarming,
                           capBeforeReset: capBeforeReset)
    }
}
