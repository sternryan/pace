import Foundation

public enum PaceFormatter {
    public static func resetLabel(for lane: LaneUsage, now: Date) -> String {
        let interval = lane.resetDate.timeIntervalSince(now)
        if interval <= 0 { return "resets shortly" }
        if interval < 24 * 3600 {
            let hours = Int(interval) / 3600
            let minutes = (Int(interval) % 3600) / 60
            return hours > 0 ? "resets in \(hours)h \(minutes)m" : "resets in \(minutes)m"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE h:mm a"
        return "resets \(formatter.string(from: lane.resetDate))"
    }

    public static func projectionLabel(capDate: Date, resetDate: Date, capBeforeReset: Bool) -> String {
        guard capBeforeReset else { return "after reset — resets first" }
        let hours = max(0, Int(resetDate.timeIntervalSince(capDate)) / 3600)
        return hours <= 0 ? "before reset" : "~\(hours)h before reset"
    }

    public static func ageLabel(since date: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(date)) / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        return hours < 48 ? "\(hours)h ago" : "\(hours / 24)d ago"
    }
}
