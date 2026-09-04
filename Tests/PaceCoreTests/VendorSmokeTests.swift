import XCTest
@testable import PaceCore

final class VendorSmokeTests: XCTestCase {
    func testClaudeLogScannerParsesFixtureDirectory() async throws {
        // Fixture: one Claude Code JSONL with two assistant messages carrying `usage` blocks, plus one garbage line.
        let (home, now) = try FixtureWriter.claudeProjects(messagesAgoSeconds: [600, 600], garbageLines: 1)

        // No CLAUDE_CONFIG_DIR / XDG_CONFIG_HOME set: the scanner falls back to `homeDirectory()/.claude`.
        let scanner = ClaudeLogUsageScanner(
            environment: ProcessEnvironmentReader(processEnvironment: [:]),
            homeDirectory: { home },
            incrementalScanner: IncrementalJSONLScanner<ClaudeLogUsageScanner.EntryOrUnparsed>(
                persistence: nil
            )
        )
        let scan = await scanner.scan(daysBack: 2, now: now, pricing: ModelPricing.empty)
        XCTAssertNotNil(scan)
    }
}
