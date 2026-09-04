import XCTest
@testable import PaceCore

final class CodexProviderTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func testFallsBackToSessionFilesWhenAuthMissing() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #"{"payload":{"rate_limits":{"primary":{"used_percent":11,"window_minutes":300,"resets_at":1800003600}}}}"#
            .write(to: dir.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8)
        let p = CodexProvider(authStore: CodexAuthStore(fileURL: URL(fileURLWithPath: "/nonexistent")),
                              client: CodexUsageClient(session: .shared),
                              sessions: CodexSessionUsageSource(sessionsDirectory: dir))
        let s = await p.fetch(now: now)
        XCTAssertEqual(s.source, .localFallback)
        XCTAssertEqual(s.lanes.first?.percentUsed, 11)
        XCTAssertEqual(s.error, .needsLogin("run `codex login`"))
    }
}
