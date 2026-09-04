import Foundation
@testable import PaceCore

/// Shared fixture builder for the vendored Claude log scanner, factored out of `VendorSmokeTests`
/// (Task 7) so `SpendProviderTests` (Task 8) can reuse the exact same JSONL shape.
enum FixtureWriter {
    /// Writes `<home>/.claude/projects/p1/s.jsonl` with two valid `assistant` usage lines — one
    /// `messagesAgoSeconds[0]` seconds before `now`, the other `messagesAgoSeconds[1]` seconds before —
    /// plus `garbageLines` lines of non-JSON text between them, and returns `(home, now)`. `home` is
    /// what `SpendProvider`'s `claudeHome:` expects (the scanner appends `.claude/projects` itself).
    ///
    /// Token math: line 1 is `1000 input + 200 output + 0 cache read + 0 cache create = 1200`; line 2
    /// is `3000 + 100 + 500 + 0 = 3600`; combined `4800`, matching `SpendProviderTests`' assertion.
    static func claudeProjects(
        messagesAgoSeconds: [Int], garbageLines: Int
    ) throws -> (home: URL, now: Date) {
        precondition(messagesAgoSeconds.count == 2, "fixture is two messages, matching Task 7's smoke test")
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = home.appendingPathComponent(".claude/projects/p1")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // `now` is snapped to an exact UTC hour boundary so both messages (600/700s before it) land
        // in the single, fully-closed PREVIOUS hour bucket — `BurnSeries.tokens(for:from:to:)` pro-
        // rates a bucket by how much of its hour overlaps the query window, so an arbitrary wall-clock
        // `now` mid-hour would make the still-forming CURRENT hour bucket only partially overlap the
        // trailing-1-hour window and undercount, making the token assertion time-of-day-flaky.
        let rawNow = Date().timeIntervalSince1970
        let now = Date(timeIntervalSince1970: (rawNow / 3600).rounded(.down) * 3600)
        let iso = ISO8601DateFormatter()
        let ts1 = iso.string(from: now.addingTimeInterval(-Double(messagesAgoSeconds[0])))
        let ts2 = iso.string(from: now.addingTimeInterval(-Double(messagesAgoSeconds[1])))

        var lines: [String] = [
            #"{"type":"assistant","timestamp":"\#(ts1)","message":{"model":"claude-sonnet-5","usage":{"input_tokens":1000,"output_tokens":200,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        ]
        lines.append(contentsOf: Array(repeating: "this is not json", count: garbageLines))
        lines.append(
            #"{"type":"assistant","timestamp":"\#(ts2)","message":{"model":"claude-sonnet-5","usage":{"input_tokens":3000,"output_tokens":100,"cache_read_input_tokens":500,"cache_creation_input_tokens":0}}}"#
        )

        try lines.joined(separator: "\n").write(
            to: dir.appendingPathComponent("s.jsonl"), atomically: true, encoding: .utf8
        )
        return (home, now)
    }
}
