import Foundation

public enum PaceCalculator {
    /// No ahead-of-pace verdict (and no projection) until the window holds
    /// this much history — a burst in the first minutes of a fresh window
    /// says nothing about sustained pace and flashed the icon red in v1.
    /// Kept equal to `minimumElapsedForStatus` so v2's `reading(for:now:)`
    /// and the newer `status(for:now:)` never disagree about "too early".
    public static let minimumElapsedForVerdict: TimeInterval = minimumElapsedForStatus

    public static func reading(for lane: LaneUsage, now: Date) -> PaceReading {
        guard let windowLength = lane.windowLength, windowLength > 0 else {
            return PaceReading(lane: lane, percentElapsed: nil, isAheadOfPace: false,
                               projectedCapDate: nil, isAlarmed: lane.severity.isAlarming,
                               capBeforeReset: nil)
        }

        let windowStart = lane.resetDate.addingTimeInterval(-windowLength)
        let elapsed = max(0, min(now.timeIntervalSince(windowStart), windowLength))
        let percentElapsed = Int((elapsed / windowLength) * 100)
        // Single source of truth for "ahead" (spec §3.3's 15-minute guard,
        // 5-point slack) — this used to be a separate, looser rule (10-minute
        // guard, no slack) that could disagree with `status(for:now:)`. A
        // capped lane must still alarm the v2 icon path, so it counts as
        // ahead here even though `status` reports it as its own case.
        let laneStatus = status(for: lane, now: now)
        let ahead = laneStatus == .ahead || laneStatus == .capped

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

public enum PaceStatus: String, Codable, Sendable { case tooEarly, onPace, ahead, capped }

extension PaceCalculator {
    /// Spec §3.3: 15-minute guard, 5-point slack.
    public static let minimumElapsedForStatus: TimeInterval = 15 * 60
    public static let slackPercent = 5

    public static func elapsedFraction(for lane: LaneUsage, now: Date) -> Double? {
        guard let w = lane.windowLength, w > 0 else { return nil }
        let start = lane.resetDate.addingTimeInterval(-w)
        return max(0, min(now.timeIntervalSince(start), w)) / w
    }

    public static func status(for lane: LaneUsage, now: Date) -> PaceStatus {
        if lane.percentUsed >= 100 { return .capped }
        guard let w = lane.windowLength, w > 0 else { return .onPace }
        let start = lane.resetDate.addingTimeInterval(-w)
        let elapsed = now.timeIntervalSince(start)
        if elapsed < minimumElapsedForStatus { return .tooEarly }
        let elapsedPct = Int((max(0, min(elapsed, w)) / w) * 100)
        return lane.percentUsed > elapsedPct + slackPercent ? .ahead : .onPace
    }
}
