import XCTest
@testable import PaceCore

final class ApiUsageNormalizerTests: XCTestCase {
    // Structure captured live from /api/oauth/usage on 2026-08-19 (Max plan).
    // Opaque feature-flag keys reduced to two stand-ins; numbers/dates kept.
    private let currentGeneration = """
    {
      "some_flag_key": true, "another_flag": {"nested": 1},
      "limits": [
        {"kind": "session", "group": "session", "percent": 67, "severity": "normal",
         "resets_at": "2026-08-19T22:50:00.109754+00:00", "scope": null, "is_active": true},
        {"kind": "weekly_all", "group": "weekly", "percent": 43, "severity": "warning",
         "resets_at": "2026-08-22T21:00:00.109771+00:00", "scope": null, "is_active": false},
        {"kind": "weekly_scoped", "group": "weekly", "percent": 60, "severity": "normal",
         "resets_at": "2026-08-22T21:00:00.109937+00:00",
         "scope": {"model": {"id": null, "display_name": "Fable"}, "surface": null}, "is_active": false}
      ],
      "extra_usage": {"is_enabled": false, "monthly_limit": 5000, "used_credits": 0.0,
                      "utilization": 0.0, "currency": "USD", "disabled_reason": "out_of_credits"},
      "spend": {"used": {"amount_minor": 0, "currency": "USD", "exponent": 2}, "percent": 0,
                "severity": "normal", "enabled": false},
      "five_hour": {"utilization": 67.0, "resets_at": "2026-08-19T22:50:00.109754+00:00"},
      "seven_day": {"utilization": 43.0, "resets_at": "2026-08-22T21:00:00.109771+00:00"}
    }
    """.data(using: .utf8)!

    private let legacyGeneration = """
    {
      "five_hour": {"utilization": 61.0, "resets_at": "2026-08-19T22:50:00+00:00"},
      "seven_day": {"utilization": 36.0, "resets_at": "2026-08-22T21:00:00+00:00"},
      "extra_usage": {"is_enabled": true, "used_credits": 1234}
    }
    """.data(using: .utf8)!

    private let now = Date(timeIntervalSince1970: 1_787_200_000)

    func testCurrentGenerationProducesThreeLanesInDisplayOrder() throws {
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: currentGeneration, now: now))
        XCTAssertEqual(snapshot.lanes.map(\.kind), [.session, .allModelsWeek, .fableWeek])
        XCTAssertEqual(snapshot.lanes[0].percentUsed, 67)
        XCTAssertEqual(snapshot.lanes[0].windowLength, 5 * 3600)
        XCTAssertEqual(snapshot.lanes[1].severity, .warning)
        XCTAssertEqual(snapshot.lanes[1].windowLength, 7 * 24 * 3600)
        XCTAssertEqual(snapshot.lanes[2].displayNameOverride, "Fable")
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testScopedLaneIdentityIsKindPlusScopeNotName() throws {
        // A renamed model must relabel the lane, not break it.
        let renamed = String(data: currentGeneration, encoding: .utf8)!
            .replacingOccurrences(of: "\"Fable\"", with: "\"Meridian\"")
            .data(using: .utf8)!
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: renamed, now: now))
        XCTAssertEqual(snapshot.lanes[2].kind, .fableWeek)
        XCTAssertEqual(snapshot.lanes[2].displayNameOverride, "Meridian")
    }

    func testLegacyGenerationProducesTwoLanesAndOverage() throws {
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: legacyGeneration, now: now))
        XCTAssertEqual(snapshot.lanes.map(\.kind), [.session, .allModelsWeek])
        XCTAssertEqual(snapshot.lanes[0].percentUsed, 61)
        XCTAssertEqual(snapshot.extraUsage, ExtraUsage(dollarsUsed: 12.34, isEnabled: true))
    }

    func testExtraUsagePrefersExtraUsageObjectOverSpend() throws {
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: currentGeneration, now: now))
        XCTAssertEqual(snapshot.extraUsage, ExtraUsage(dollarsUsed: 0, isEnabled: false))
    }

    func testMissingScopedLaneStillParses() throws {
        // A plan without a per-model weekly lane renders two lanes, not zero.
        let fixture = """
        {"limits": [
           {"kind": "session", "percent": 10, "severity": "normal",
            "resets_at": "2026-08-19T22:50:00+00:00"},
           {"kind": "weekly_all", "percent": 20, "severity": "normal",
            "resets_at": "2026-08-22T21:00:00+00:00"}]}
        """.data(using: .utf8)!
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: fixture, now: now))
        XCTAssertEqual(snapshot.lanes.map(\.kind), [.session, .allModelsWeek])
        XCTAssertNil(snapshot.extraUsage)
    }

    func testGarbageAndShapeDriftReturnNilNotCrash() {
        XCTAssertNil(ApiUsageNormalizer.snapshot(fromJSON: Data("not json".utf8), now: now))
        XCTAssertNil(ApiUsageNormalizer.snapshot(fromJSON: Data("{}".utf8), now: now))
        // limits present but entries missing required fields, and no legacy
        // fallback objects → nil (shape changed; caller reports parseError).
        let drifted = Data(#"{"limits": [{"kind": "session", "pct": 5}]}"#.utf8)
        XCTAssertNil(ApiUsageNormalizer.snapshot(fromJSON: drifted, now: now))
    }

    func testStringPercentIsCoercedNotDropped() throws {
        // Type drift the endpoint could plausibly ship (67 → "67"): coerce
        // numeric strings rather than silently dropping the lane; drop only
        // what genuinely can't be read.
        let fixture = """
        {"limits": [
           {"kind": "session", "percent": "67", "severity": "normal",
            "resets_at": "2026-08-19T22:50:00+00:00"}]}
        """.data(using: .utf8)!
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: fixture, now: now))
        XCTAssertEqual(snapshot.lanes[0].percentUsed, 67)
    }

    func testUnparseableResetDateDropsLaneRatherThanGuessing() throws {
        let fixture = """
        {"limits": [
           {"kind": "session", "percent": 10, "severity": "normal", "resets_at": "soonish"},
           {"kind": "weekly_all", "percent": 20, "severity": "normal",
            "resets_at": "2026-08-22T21:00:00+00:00"}]}
        """.data(using: .utf8)!
        let snapshot = try XCTUnwrap(ApiUsageNormalizer.snapshot(fromJSON: fixture, now: now))
        XCTAssertEqual(snapshot.lanes.map(\.kind), [.allModelsWeek])
    }
}
