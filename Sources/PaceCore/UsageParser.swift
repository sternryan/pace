import Foundation

public enum UsageParser {
    public static func parsePercent(_ text: String) -> Int? {
        guard let range = text.range(of: #"\d{1,3}%"#, options: .regularExpression) else { return nil }
        let digits = text[range].dropLast()
        return Int(digits)
    }

    public static func parseRelativeReset(_ text: String, now: Date) -> Date? {
        guard text.localizedCaseInsensitiveContains("resets in") else { return nil }
        var totalSeconds: TimeInterval = 0
        var found = false

        if let hrRange = text.range(of: #"\d+\s*hr"#, options: .regularExpression) {
            let digits = text[hrRange].prefix { $0.isNumber }
            if let hrs = Double(digits) { totalSeconds += hrs * 3600; found = true }
        }
        if let minRange = text.range(of: #"\d+\s*min"#, options: .regularExpression) {
            let digits = text[minRange].prefix { $0.isNumber }
            if let mins = Double(digits) { totalSeconds += mins * 60; found = true }
        }

        guard found else { return nil }
        return now.addingTimeInterval(totalSeconds)
    }

    public static func parseWeekdayReset(_ text: String, now: Date, calendar: Calendar = .current) -> Date? {
        guard text.localizedCaseInsensitiveContains("resets") else { return nil }

        let weekdayNames: [String: Int] = [
            "sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7
        ]
        guard let wdRange = text.range(of: #"(?i)\b(sun|mon|tue|wed|thu|fri|sat)"#, options: .regularExpression),
              let targetWeekday = weekdayNames[text[wdRange].lowercased()] else { return nil }

        guard let timeRange = text.range(of: #"\d{1,2}:\d{2}\s*(AM|PM)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let timeStr = text[timeRange]
        let parts = timeStr.split(separator: ":")
        guard parts.count == 2, let hourRaw = Int(parts[0]) else { return nil }

        let minutePart = parts[1]
        guard let minute = Int(minutePart.prefix { $0.isNumber }) else { return nil }
        let isPM = minutePart.uppercased().contains("PM")

        var hour = hourRaw % 12
        if isPM { hour += 12 }

        return calendar.nextDate(
            after: now.addingTimeInterval(-1),
            matching: DateComponents(hour: hour, minute: minute, weekday: targetWeekday),
            matchingPolicy: .nextTimePreservingSmallerComponents
        )
    }
}
