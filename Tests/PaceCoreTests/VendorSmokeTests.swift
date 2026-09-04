import XCTest
@testable import PaceCore

final class VendorSmokeTests: XCTestCase {
    func testClaudeLogScannerParsesFixtureDirectory() async throws {
        // Fixture: one Claude Code JSONL with two assistant messages carrying `usage` blocks, plus one garbage line.
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = home.appendingPathComponent(".claude/projects/p1")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date()
        let iso = ISO8601DateFormatter().string(from: now.addingTimeInterval(-600))
        let lines = [
          #"{"type":"assistant","timestamp":"\#(iso)","message":{"model":"claude-sonnet-5","usage":{"input_tokens":1000,"output_tokens":200,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#,
          "this is not json",
          #"{"type":"assistant","timestamp":"\#(iso)","message":{"model":"claude-sonnet-5","usage":{"input_tokens":3000,"output_tokens":100,"cache_read_input_tokens":500,"cache_creation_input_tokens":0}}}"#
        ].joined(separator: "\n")
        try lines.write(to: dir.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)

        // No CLAUDE_CONFIG_DIR / XDG_CONFIG_HOME set: the scanner falls back to `homeDirectory()/.claude`.
        let scanner = ClaudeLogUsageScanner(
            environment: ProcessEnvironmentReader(processEnvironment: [:]),
            homeDirectory: { home },
            incrementalScanner: IncrementalJSONLScanner<ClaudeLogUsageScanner.Entry>(
                persistence: nil
            )
        )
        let scan = await scanner.scan(daysBack: 2, now: now, pricing: ModelPricing.empty)
        XCTAssertNotNil(scan)
    }
}
