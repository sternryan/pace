import Foundation

public enum PaceCalculator {
    public static func reading(for lane: LaneUsage, now: Date) -> PaceReading {
        guard let windowLength = lane.windowLength, windowLength > 0 else {
            return PaceReading(lane: lane, percentElapsed: nil, isAheadOfPace: false, projectedCapDate: nil)
        }

        let windowStart = lane.resetDate.addingTimeInterval(-windowLength)
        let elapsed = max(0, min(now.timeIntervalSince(windowStart), windowLength))
        let percentElapsed = Int((elapsed / windowLength) * 100)
        let ahead = lane.percentUsed > percentElapsed

        var projectedCapDate: Date? = nil
        if ahead, elapsed > 0, lane.percentUsed > 0 {
            let ratePerSecond = Double(lane.percentUsed) / elapsed
            let secondsTo100 = 100.0 / ratePerSecond
            projectedCapDate = windowStart.addingTimeInterval(secondsTo100)
        }

        return PaceReading(lane: lane, percentElapsed: percentElapsed, isAheadOfPace: ahead, projectedCapDate: projectedCapDate)
    }
}
