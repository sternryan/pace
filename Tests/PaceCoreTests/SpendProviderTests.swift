import XCTest
@testable import PaceCore

final class SpendProviderTests: XCTestCase {
    func testHourlyBucketsAndUnparsedCount() async throws {
        let (claudeHome, now) = try FixtureWriter.claudeProjects(messagesAgoSeconds: [600, 700], garbageLines: 1)

        // A fixed, network-free pricing snapshot with an exact rate for the fixture's model — real
        // dollar values don't matter here, only that the lines are priceable (else they're excluded
        // from `entries`/`unknownModelsByDay` and the token assertion below would see 0, not 4800).
        let pricing = ModelPricing(
            supplement: PricingSupplement(),
            primary: PricingCatalog(entries: [
                "claude-sonnet-5": ModelRates(
                    inputPerMillion: 3, outputPerMillion: 15, cacheWritePerMillion: 3.75, cacheReadPerMillion: 0.3
                )
            ]),
            secondary: PricingCatalog()
        )

        let provider = SpendProvider(
            claudeHome: claudeHome,
            codexHome: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            cacheDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            environment: ProcessEnvironmentReader(processEnvironment: [:]),
            pricing: pricing
        )

        let snapshot = await provider.fetch(now: now)
        XCTAssertEqual(snapshot.provider, .spend)
        let burn = try XCTUnwrap(snapshot.burn)
        XCTAssertEqual(burn.unparsedLines, 1)
        XCTAssertEqual(burn.tokens(for: .claude, from: now.addingTimeInterval(-3600), to: now), 4800)
        XCTAssertEqual(burn.hourly.filter { $0.provider == .codex }.count, 0)
    }
}
