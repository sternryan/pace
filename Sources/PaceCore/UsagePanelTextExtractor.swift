import Foundation

public enum UsagePanelTextExtractor {
    private static let laneAnchors: [(LaneKind, String)] = [
        (.session, "Current session"),
        (.allModelsWeek, "All models"),
        (.fableWeek, "Fable")
    ]

    public static func extractLanes(from panelText: String, now: Date, sessionWindowLength: TimeInterval?) -> [LaneUsage]? {
        // Line-anchored match, not a bare substring: "Fable" as a lane header
        // stands alone on its own line, but claude.ai's own "Fable 5 is still
        // included with your Max plan." banner also contains the substring
        // "Fable" and would otherwise be matched first — see review finding.
        let found = laneAnchors.compactMap { kind, anchor -> (LaneKind, Range<String.Index>)? in
            let pattern = "(?m)^\(NSRegularExpression.escapedPattern(for: anchor))$"
            return panelText.range(of: pattern, options: .regularExpression).map { (kind, $0) }
        }
        guard found.count == laneAnchors.count else { return nil }

        let sorted = found.sorted { $0.1.lowerBound < $1.1.lowerBound }
        var lanes: [LaneUsage] = []

        for (index, entry) in sorted.enumerated() {
            let (kind, range) = entry
            let chunkStart = range.upperBound
            let chunkEnd = index + 1 < sorted.count ? sorted[index + 1].1.lowerBound : panelText.endIndex
            let chunk = String(panelText[chunkStart..<chunkEnd])

            guard let percent = UsageParser.parsePercent(chunk) else { return nil }

            let resetDate: Date?
            let windowLength: TimeInterval?
            if kind == .session {
                resetDate = UsageParser.parseRelativeReset(chunk, now: now)
                windowLength = sessionWindowLength
            } else {
                resetDate = UsageParser.parseWeekdayReset(chunk, now: now)
                windowLength = 7 * 24 * 3600
            }

            guard let resolvedResetDate = resetDate else { return nil }
            lanes.append(LaneUsage(kind: kind, percentUsed: percent, resetDate: resolvedResetDate, windowLength: windowLength))
        }

        return lanes
    }
}
