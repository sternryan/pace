import Foundation

public struct LaneAlert: Equatable, Sendable {
    public let kind: LaneKind
    public let message: String

    public init(kind: LaneKind, message: String) {
        self.kind = kind
        self.message = message
    }
}

/// Edge-armed alerting: one notification per lane when it CROSSES into the
/// alarm state; re-armed when it drops back below or its window resets.
/// Level-triggered alerting would re-fire every refresh tick — notification
/// fatigue is how a signal gets ignored.
public struct NotificationGovernor {
    private struct Armed: Equatable { let resetDate: Date }
    private var notified: [LaneKind: Armed] = [:]

    public init() {}

    public mutating func alertsFor(readings: [PaceReading]) -> [LaneAlert] {
        var alerts: [LaneAlert] = []
        for reading in readings {
            let kind = reading.lane.kind
            if reading.isAlarmed {
                let alreadyNotifiedThisWindow = notified[kind]?.resetDate == reading.lane.resetDate
                if !alreadyNotifiedThisWindow {
                    notified[kind] = Armed(resetDate: reading.lane.resetDate)
                    // isAlarmed covers two distinct truths: locally ahead of
                    // pace, or server-reported critical/exceeded (which can
                    // fire on a lane that is BEHIND pace). Say the right one.
                    let message = reading.isAheadOfPace
                        ? "\(reading.lane.effectiveDisplayName) is at \(reading.lane.percentUsed)% and running ahead of its window."
                        : "\(reading.lane.effectiveDisplayName) is at \(reading.lane.percentUsed)% — the server reports it \(reading.lane.severity.rawValue)."
                    alerts.append(LaneAlert(kind: kind, message: message))
                }
            } else {
                notified[kind] = nil // dropped below: re-arm
            }
        }
        return alerts
    }
}
