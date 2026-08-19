import XCTest
@testable import PaceCore

final class NotificationGovernorTests: XCTestCase {
    private func reading(_ kind: LaneKind, alarmed: Bool, resetDate: Date) -> PaceReading {
        let lane = LaneUsage(kind: kind, percentUsed: 50, resetDate: resetDate, windowLength: 5 * 3600)
        return PaceReading(lane: lane, percentElapsed: 20, isAheadOfPace: alarmed,
                           projectedCapDate: nil, isAlarmed: alarmed, capBeforeReset: nil)
    }

    func testFiresOnceOnUpwardCrossingOnly() {
        var governor = NotificationGovernor()
        let reset = Date(timeIntervalSince1970: 1_787_204_000)
        XCTAssertTrue(governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset)]).count == 1)
        // Same alarmed state on the next tick: already notified — stay silent.
        XCTAssertTrue(governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset)]).isEmpty)
    }

    func testReArmsWhenLaneDropsBackBelow() {
        var governor = NotificationGovernor()
        let reset = Date(timeIntervalSince1970: 1_787_204_000)
        _ = governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset)])
        _ = governor.alertsFor(readings: [reading(.session, alarmed: false, resetDate: reset)])
        XCTAssertEqual(governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset)]).count, 1)
    }

    func testReArmsOnWindowReset() {
        var governor = NotificationGovernor()
        let reset1 = Date(timeIntervalSince1970: 1_787_204_000)
        _ = governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset1)])
        // New window (later resetDate), still alarmed → a fresh event.
        let reset2 = reset1.addingTimeInterval(5 * 3600)
        XCTAssertEqual(governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset2)]).count, 1)
    }

    func testIndependentPerLane() {
        var governor = NotificationGovernor()
        let reset = Date(timeIntervalSince1970: 1_787_204_000)
        _ = governor.alertsFor(readings: [reading(.session, alarmed: true, resetDate: reset)])
        let alerts = governor.alertsFor(readings: [
            reading(.session, alarmed: true, resetDate: reset),
            reading(.allModelsWeek, alarmed: true, resetDate: reset)
        ])
        XCTAssertEqual(alerts.map(\.kind), [.allModelsWeek])
    }
}
