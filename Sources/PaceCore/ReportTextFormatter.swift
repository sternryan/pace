import Foundation

public enum ReportTextFormatter {
    public static func render(_ r: PaceReport, now: Date, ageStale: Bool = false) -> String {
        var lines: [String] = []
        lines.append("pace  \(PaceFormatter.ageLabel(since: r.generatedAt, now: now))\(r.stale || ageStale ? "  [STALE]" : "")")
        if let h = r.headline { lines.append("HEADLINE  \(h.verdict)") }
        if let a = r.advice { lines.append("ADVICE    \(a)") }
        lines.append("")
        for w in r.windows { lines.append("  \(w.status == .ahead || w.status == .capped ? "↑" : " ") \(w.verdict)  [\(w.source.rawValue)]") }
        lines.append("")
        lines.append("smithy    \(r.laneState?.rawValue ?? "unknown")")
        for p in r.providers where p.provider != .smithy {
            lines.append("\(p.provider.rawValue.padding(toLength: 9, withPad: " ", startingAt: 0)) \(p.source.rawValue)\(p.error.map { "  ⚠ \($0)" } ?? "")")
        }
        if let b = r.burn, b.unparsedLines > 0 { lines.append("spend     \(b.unparsedLines) unparsed log lines") }
        return lines.joined(separator: "\n") + "\n"
    }
}
