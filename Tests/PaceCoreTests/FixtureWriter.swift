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

    /// Writes `<home>/.codex/sessions/2026/09/04/rollout-x.jsonl` with two `event_msg`/`token_count`
    /// lines carrying `last_token_usage` — the shape `CodexLogFileParser.parse` accepts (top-level
    /// `type`/`timestamp`, `payload.type == "token_count"`, `payload.model`, `payload.info
    /// .last_token_usage`) — one `messagesAgoSeconds[0]` seconds before `now`, the other
    /// `messagesAgoSeconds[1]` seconds before, plus `garbageLines` lines of non-JSON text between
    /// them, and returns `(home, now)`. `home` is what `SpendProvider`'s `codexHome:` expects (the
    /// scanner appends `.codex` itself, then discovers `sessions/`). No `session_meta`/
    /// `turn_context` lines are needed: the parser only requires those to be ABSENT of "child
    /// session" replay metadata, and `event_msg`/`token_count` alone parses standalone.
    ///
    /// Token math: line 1's `last_token_usage` is `1000 input + 200 output + 0 cached, total_tokens:
    /// 1200`; line 2 is `3000 + 100 + 500 cached, total_tokens: 3600`; combined `4800` — `event.total`
    /// (what `aggregate` feeds into `accumulator`/`entries`) is the raw `total_tokens` field, not a
    /// recomputed sum, so it's set explicitly on each line rather than left to `RawUsage`'s fallback.
    static func codexSessions(
        messagesAgoSeconds: [Int], garbageLines: Int
    ) throws -> (home: URL, now: Date) {
        precondition(messagesAgoSeconds.count == 2, "fixture is two messages, matching the Claude fixture")
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let dir = home.appendingPathComponent(".codex/sessions/2026/09/04")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Same UTC-hour-boundary snap as `claudeProjects`, and for the same reason: `BurnSeries
        // .tokens(for:from:to:)` pro-rates a bucket by how much of its hour overlaps the query
        // window, so an arbitrary wall-clock `now` mid-hour would undercount the still-forming
        // current hour and make the token assertion time-of-day-flaky.
        let rawNow = Date().timeIntervalSince1970
        let now = Date(timeIntervalSince1970: (rawNow / 3600).rounded(.down) * 3600)
        let iso = ISO8601DateFormatter()
        let ts1 = iso.string(from: now.addingTimeInterval(-Double(messagesAgoSeconds[0])))
        let ts2 = iso.string(from: now.addingTimeInterval(-Double(messagesAgoSeconds[1])))

        var lines: [String] = [
            #"{"type":"event_msg","timestamp":"\#(ts1)","payload":{"type":"token_count","model":"gpt-5","info":{"last_token_usage":{"input_tokens":1000,"cached_input_tokens":0,"output_tokens":200,"reasoning_output_tokens":0,"total_tokens":1200}}}}"#
        ]
        lines.append(contentsOf: Array(repeating: "this is not json", count: garbageLines))
        lines.append(
            #"{"type":"event_msg","timestamp":"\#(ts2)","payload":{"type":"token_count","model":"gpt-5","info":{"last_token_usage":{"input_tokens":3000,"cached_input_tokens":500,"output_tokens":100,"reasoning_output_tokens":0,"total_tokens":3600}}}}"#
        )

        try lines.joined(separator: "\n").write(
            to: dir.appendingPathComponent("rollout-x.jsonl"), atomically: true, encoding: .utf8
        )
        return (home, now)
    }
}
