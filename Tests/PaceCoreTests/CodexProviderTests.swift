import Foundation
import Testing
@testable import PaceCore

/// Unifying codex-pace back into pace (2026-09-20). codex-pace was pace v2 plus
/// two files and 186 changed lines; these cover the behaviour that is genuinely
/// NEW here rather than ported verbatim.
///
/// Context: pace v3 already unified these and was reverted 2026-09-05 because it
/// collapsed two glanceable menubar icons into one verdict line. The two icons are
/// the requirement, not an implementation detail -- see docs/NOTES-2026-09-05-v3-revert.md.
@Suite("Codex provider unification")
struct CodexProviderTests {

    // MARK: provider identity

    @Test("both providers exist and are distinguishable")
    func providersExist() {
        #expect(PaceProvider.allCases.count == 2)
        #expect(PaceProvider.claude.displayName == "Claude")
        #expect(PaceProvider.codex.displayName == "Codex")
    }

    // MARK: the cache-collision bug this refactor would otherwise introduce

    @Test("each provider caches to its own directory")
    func cacheDirectoriesDoNotCollide() {
        let claude = SnapshotCache.defaultDirectory(for: .claude)
        let codex = SnapshotCache.defaultDirectory(for: .codex)
        #expect(claude != codex, "two providers sharing one cache file clobber each other")
    }

    @Test("claude keeps the legacy cache path so existing users keep their snapshot")
    func claudeCachePathIsUnchanged() {
        #expect(SnapshotCache.defaultDirectory(for: .claude) == SnapshotCache.defaultDirectory())
    }

    // MARK: Codex rate-limit windows

    @Test("parses the primary and secondary windows from a Codex session line")
    func parsesBothWindows() throws {
        let line = """
        {"payload":{"rate_limits":{\
        "primary":{"used_percent":42.5,"window_minutes":300,"resets_at":1790000000},\
        "secondary":{"used_percent":7,"window_minutes":10080,"resets_at":1790500000}}}}
        """
        let snap = try #require(CodexRateLimitParser.snapshot(fromJSONLines: line))
        #expect(snap.lanes.count == 2)
        let primary = try #require(snap.lanes.first { $0.kind == .primary })
        #expect(primary.percentUsed == 43)                       // 42.5 rounds up
        #expect(primary.effectiveDisplayName == "5-hour window")
        let secondary = try #require(snap.lanes.first { $0.kind == .secondary })
        #expect(secondary.effectiveDisplayName == "Weekly window")
    }

    @Test("takes the LAST rate-limit event in the stream, not the first")
    func usesMostRecentEvent() throws {
        let text = """
        {"payload":{"rate_limits":{"primary":{"used_percent":10,"window_minutes":300,"resets_at":1790000000}}}}
        {"payload":{"rate_limits":{"primary":{"used_percent":90,"window_minutes":300,"resets_at":1790000000}}}}
        """
        let snap = try #require(CodexRateLimitParser.snapshot(fromJSONLines: text))
        #expect(snap.lanes.first?.percentUsed == 90)
    }

    @Test("returns nil when no line carries a rate-limit event")
    func noEventYieldsNil() {
        #expect(CodexRateLimitParser.snapshot(fromJSONLines: "{\"payload\":{}}\nnot json") == nil)
    }

    // MARK: label override, generalised from the Claude-only form

    @Test("a source-provided label is used verbatim for non-Fable lanes")
    func overrideUsedVerbatim() {
        let lane = LaneUsage(kind: .primary, percentUsed: 1, resetDate: Date(),
                             windowLength: 300, displayNameOverride: "5-hour window")
        #expect(lane.effectiveDisplayName == "5-hour window")
    }

    @Test("the Fable lane keeps its ' · week' suffix")
    func fableSuffixPreserved() {
        let lane = LaneUsage(kind: .fableWeek, percentUsed: 1, resetDate: Date(),
                             windowLength: nil, displayNameOverride: "Fable")
        #expect(lane.effectiveDisplayName == "Fable · week")
    }
}
