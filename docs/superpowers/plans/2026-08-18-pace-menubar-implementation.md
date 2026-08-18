# Pace Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build Pace, a macOS menu bar app that scrapes claude.ai's Settings → Usage page and shows current-session / all-models-week / Fable-week usage as a 3-lane monochrome pace indicator, with red signaling only when a lane is burning faster than the reset window allows.

**Architecture:** Swift Package Manager project with two targets — `PaceCore` (pure Swift: parsing, pace math, icon geometry — fully unit-testable with `swift test`, no AppKit/WebKit) and `Pace` (the SwiftUI `MenuBarExtra` app: hidden-WKWebView scraper, icon rendering, dropdown UI, preferences). No Xcode project file; built via `swift build` and wrapped into a `.app` bundle by a small script, matching this workspace's Makefile-driven conventions.

**Tech Stack:** Swift 5.9+, SwiftUI (`MenuBarExtra`, macOS 14+), WebKit (`WKWebView`), `ServiceManagement` (`SMAppService` for launch-at-login), XCTest.

**Spec:** `/Users/ryanstern/pace/docs/superpowers/specs/2026-08-18-pace-menubar-design.md`

## Global Constraints

- Target macOS 14.0+ (`LSMinimumSystemVersion` = `14.0`).
- Bundle identifier: `com.sternryan.pace`. App name: `Pace`. `LSUIElement` = `true` (no Dock icon).
- Icon is a monochrome template image by default; the only color ever shown is red, and only on a lane that is ahead of pace (fill % > elapsed % of its window). No other color is used anywhere in the icon.
- Refresh interval defaults to 360 seconds (6 minutes), user-configurable in Preferences.
- No native notifications — alerting is passive (icon color only). Do not add `UNUserNotificationCenter` calls.
- The current-session window's total length is **not assumed**. Any code that needs it must accept `nil` and degrade to "no pace tick / no projection for this lane" rather than hardcoding a guessed duration (e.g. 5 hours).
- No App Store distribution, no notarization — ad-hoc `codesign` for local install only.
- Not built with Xcode project files — Swift Package Manager + Makefile.

---

## Task 1: Project scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/PaceCore/.gitkeep` (removed once Task 2 adds real files)
- Create: `Sources/Pace/Info.plist`
- Create: `Sources/Pace/main-placeholder.swift` — temporary, deleted in Task 12 when the real `PaceApp.swift` lands
- Create: `Tests/PaceCoreTests/.gitkeep`
- Create: `Makefile`
- Create: `Scripts/build-app.sh`

**Interfaces:**
- Produces: the `PaceCore` library target and `Pace` executable target that every later task builds on.

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Pace",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PaceCore", targets: ["PaceCore"]),
        .executable(name: "Pace", targets: ["Pace"])
    ],
    targets: [
        .target(name: "PaceCore"),
        .executableTarget(name: "Pace", dependencies: ["PaceCore"]),
        .testTarget(name: "PaceCoreTests", dependencies: ["PaceCore"])
    ]
)
```

- [ ] **Step 2: Create a placeholder executable so the package builds**

`Sources/Pace/main-placeholder.swift`:

```swift
print("Pace scaffold OK — replaced by PaceApp.swift in Task 12")
```

- [ ] **Step 3: Create `Sources/Pace/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.sternryan.pace</string>
    <key>CFBundleName</key>
    <string>Pace</string>
    <key>CFBundleExecutable</key>
    <string>Pace</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
```

- [ ] **Step 4: Create the Makefile**

```makefile
.PHONY: test build run app install

test:
	swift test

build:
	swift build -c release

run:
	swift run Pace

app: build
	./Scripts/build-app.sh

install: app
	rm -rf "$$HOME/Applications/Pace.app"
	mkdir -p "$$HOME/Applications"
	cp -R .build/Pace.app "$$HOME/Applications/Pace.app"
	@echo "Installed to ~/Applications/Pace.app — launch it once manually, then enable Launch at Login in Preferences."
```

- [ ] **Step 5: Create `Scripts/build-app.sh`**

```bash
#!/bin/bash
set -euo pipefail
APP_NAME="Pace"
BUILD_DIR=".build/release"
APP_BUNDLE=".build/${APP_NAME}.app"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Sources/Pace/Info.plist "$APP_BUNDLE/Contents/Info.plist"

codesign --force --deep --sign - "$APP_BUNDLE"

echo "Built $APP_BUNDLE"
```

```bash
chmod +x Scripts/build-app.sh
mkdir -p Sources/PaceCore Tests/PaceCoreTests
touch Sources/PaceCore/.gitkeep Tests/PaceCoreTests/.gitkeep
```

- [ ] **Step 6: Verify the package builds and tests run (empty test suite is fine)**

Run: `swift build && swift test`
Expected: both succeed (test run reports 0 tests).

- [ ] **Step 7: Commit**

```bash
git add Package.swift Makefile Scripts Sources Tests
git commit -m "chore: scaffold Pace SPM project"
```

---

## Task 2: Core types — LaneKind, LaneUsage, FetchStatus, PaceReading

**Files:**
- Create: `Sources/PaceCore/LaneKind.swift`
- Create: `Sources/PaceCore/LaneUsage.swift`
- Create: `Sources/PaceCore/FetchStatus.swift`
- Create: `Sources/PaceCore/PaceReading.swift`
- Test: `Tests/PaceCoreTests/CoreTypesTests.swift`

**Interfaces:**
- Consumes: nothing (base types).
- Produces: `LaneKind` (`.session`, `.allModelsWeek`, `.fableWeek`, `.displayName: String`), `LaneUsage` (`kind`, `percentUsed: Int`, `resetDate: Date`, `windowLength: TimeInterval?`), `FetchStatus` (`.ok`, `.needsLogin`, `.parseError(String)`), `PaceReading` (`lane: LaneUsage`, `percentElapsed: Int?`, `isAheadOfPace: Bool`, `projectedCapDate: Date?`) — used by every later task.

- [ ] **Step 1: Write the test**

`Tests/PaceCoreTests/CoreTypesTests.swift`:

```swift
import XCTest
@testable import PaceCore

final class CoreTypesTests: XCTestCase {
    func testLaneKindDisplayNames() {
        XCTAssertEqual(LaneKind.session.displayName, "Current session")
        XCTAssertEqual(LaneKind.allModelsWeek.displayName, "All models · week")
        XCTAssertEqual(LaneKind.fableWeek.displayName, "Fable · week")
    }

    func testLaneKindIsHashable() {
        let set: Set<LaneKind> = [.session, .session, .fableWeek]
        XCTAssertEqual(set.count, 2)
    }

    func testLaneUsageEquality() {
        let date = Date(timeIntervalSince1970: 0)
        let a = LaneUsage(kind: .session, percentUsed: 21, resetDate: date, windowLength: nil)
        let b = LaneUsage(kind: .session, percentUsed: 21, resetDate: date, windowLength: nil)
        XCTAssertEqual(a, b)
    }

    func testFetchStatusEquality() {
        XCTAssertEqual(FetchStatus.parseError("x"), FetchStatus.parseError("x"))
        XCTAssertNotEqual(FetchStatus.parseError("x"), FetchStatus.parseError("y"))
        XCTAssertNotEqual(FetchStatus.ok, FetchStatus.needsLogin)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter CoreTypesTests`
Expected: FAIL — `LaneKind`/`LaneUsage`/`FetchStatus` not found.

- [ ] **Step 3: Implement**

`Sources/PaceCore/LaneKind.swift`:

```swift
public enum LaneKind: String, CaseIterable, Hashable, Sendable {
    case session
    case allModelsWeek
    case fableWeek

    public var displayName: String {
        switch self {
        case .session: return "Current session"
        case .allModelsWeek: return "All models · week"
        case .fableWeek: return "Fable · week"
        }
    }
}
```

`Sources/PaceCore/LaneUsage.swift`:

```swift
import Foundation

public struct LaneUsage: Equatable, Sendable {
    public let kind: LaneKind
    public let percentUsed: Int
    public let resetDate: Date
    /// Total length of this lane's reset window. `nil` when not yet known —
    /// callers MUST treat `nil` as "can't compute pace for this lane" and
    /// never substitute a guessed duration. See Global Constraints.
    public let windowLength: TimeInterval?

    public init(kind: LaneKind, percentUsed: Int, resetDate: Date, windowLength: TimeInterval?) {
        self.kind = kind
        self.percentUsed = percentUsed
        self.resetDate = resetDate
        self.windowLength = windowLength
    }
}
```

`Sources/PaceCore/FetchStatus.swift`:

```swift
public enum FetchStatus: Equatable, Sendable {
    case ok
    case needsLogin
    case parseError(String)
}
```

`Sources/PaceCore/PaceReading.swift`:

```swift
import Foundation

public struct PaceReading: Equatable, Sendable {
    public let lane: LaneUsage
    public let percentElapsed: Int?
    public let isAheadOfPace: Bool
    public let projectedCapDate: Date?

    public init(lane: LaneUsage, percentElapsed: Int?, isAheadOfPace: Bool, projectedCapDate: Date?) {
        self.lane = lane
        self.percentElapsed = percentElapsed
        self.isAheadOfPace = isAheadOfPace
        self.projectedCapDate = projectedCapDate
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter CoreTypesTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PaceCore Tests/PaceCoreTests
git commit -m "feat: add core usage/pace types"
```

---

## Task 3: UsageParser — percent and reset-time parsing

**Files:**
- Create: `Sources/PaceCore/UsageParser.swift`
- Test: `Tests/PaceCoreTests/UsageParserTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `UsageParser.parsePercent(_:) -> Int?`, `UsageParser.parseRelativeReset(_:now:) -> Date?`, `UsageParser.parseWeekdayReset(_:now:calendar:) -> Date?` — consumed by Task 7 (`UsagePanelTextExtractor`).

**Note:** the fixture strings below are reconstructed verbatim from the design-time screenshots of claude.ai's Settings → Usage panel ("21% used", "Resets in 3 hr 53 min", "Resets Sat 2:00 PM"). They are the best available data at plan-writing time. Task 6 captures the real live DOM text; if it differs from these fixtures in format, come back and adjust this task's regexes/tests before relying on Task 7/8.

- [ ] **Step 1: Write the test**

`Tests/PaceCoreTests/UsageParserTests.swift`:

```swift
import XCTest
@testable import PaceCore

final class UsageParserTests: XCTestCase {
    func testParsePercent() {
        XCTAssertEqual(UsageParser.parsePercent("21% used"), 21)
        XCTAssertEqual(UsageParser.parsePercent("16% used"), 16)
        XCTAssertEqual(UsageParser.parsePercent("100% used"), 100)
        XCTAssertNil(UsageParser.parsePercent("no percent here"))
    }

    func testParseRelativeReset() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let result = UsageParser.parseRelativeReset("Resets in 3 hr 53 min", now: now)
        XCTAssertEqual(result, now.addingTimeInterval(3 * 3600 + 53 * 60))
    }

    func testParseRelativeResetMinutesOnly() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let result = UsageParser.parseRelativeReset("Resets in 45 min", now: now)
        XCTAssertEqual(result, now.addingTimeInterval(45 * 60))
    }

    func testParseRelativeResetReturnsNilForUnrelatedText() {
        XCTAssertNil(UsageParser.parseRelativeReset("Resets Sat 2:00 PM", now: Date()))
    }

    func testParseWeekdayReset() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Tuesday 2026-08-18 12:00 UTC
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))!
        let result = UsageParser.parseWeekdayReset("Resets Sat 2:00 PM", now: now, calendar: calendar)
        let expected = calendar.date(from: DateComponents(year: 2026, month: 8, day: 22, hour: 14))!
        XCTAssertEqual(result, expected)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter UsageParserTests`
Expected: FAIL — `UsageParser` not found.

- [ ] **Step 3: Implement**

`Sources/PaceCore/UsageParser.swift`:

```swift
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter UsageParserTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PaceCore/UsageParser.swift Tests/PaceCoreTests/UsageParserTests.swift
git commit -m "feat: add UsageParser for percent and reset-time text"
```

---

## Task 4: PaceCalculator + PaceFormatter

**Files:**
- Create: `Sources/PaceCore/PaceCalculator.swift`
- Create: `Sources/PaceCore/PaceFormatter.swift`
- Test: `Tests/PaceCoreTests/PaceCalculatorTests.swift`

**Interfaces:**
- Consumes: `LaneUsage`, `PaceReading` (Task 2).
- Produces: `PaceCalculator.reading(for:now:) -> PaceReading`, `PaceFormatter.resetLabel(for:now:) -> String`, `PaceFormatter.projectionLabel(capDate:resetDate:) -> String` — consumed by Task 9 (AppState) and Task 11 (MenuView).

- [ ] **Step 1: Write the test**

`Tests/PaceCoreTests/PaceCalculatorTests.swift`:

```swift
import XCTest
@testable import PaceCore

final class PaceCalculatorTests: XCTestCase {
    func testUnknownWindowLengthProducesNoTickOrProjection() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lane = LaneUsage(kind: .session, percentUsed: 70, resetDate: now.addingTimeInterval(3600), windowLength: nil)
        let reading = PaceCalculator.reading(for: lane, now: now)
        XCTAssertNil(reading.percentElapsed)
        XCTAssertFalse(reading.isAheadOfPace)
        XCTAssertNil(reading.projectedCapDate)
    }

    func testAheadOfPaceComputesProjectionBeforeReset() {
        // 7-day window, reset in 4 days (so 3 of 7 days elapsed = ~43%), 70% used -> ahead.
        let windowLength: TimeInterval = 7 * 24 * 3600
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetDate = now.addingTimeInterval(4 * 24 * 3600)
        let lane = LaneUsage(kind: .fableWeek, percentUsed: 70, resetDate: resetDate, windowLength: windowLength)

        let reading = PaceCalculator.reading(for: lane, now: now)

        XCTAssertEqual(reading.percentElapsed, 42) // 3/7 days, truncated
        XCTAssertTrue(reading.isAheadOfPace)
        XCTAssertNotNil(reading.projectedCapDate)
        XCTAssertLessThan(reading.projectedCapDate!, resetDate)
    }

    func testBehindPaceHasNoProjection() {
        let windowLength: TimeInterval = 7 * 24 * 3600
        let now = Date(timeIntervalSince1970: 1_000_000)
        let resetDate = now.addingTimeInterval(2 * 24 * 3600) // 5/7 elapsed = ~71%
        let lane = LaneUsage(kind: .allModelsWeek, percentUsed: 20, resetDate: resetDate, windowLength: windowLength)

        let reading = PaceCalculator.reading(for: lane, now: now)

        XCTAssertFalse(reading.isAheadOfPace)
        XCTAssertNil(reading.projectedCapDate)
    }

    func testResetLabelUnderADay() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lane = LaneUsage(kind: .session, percentUsed: 21, resetDate: now.addingTimeInterval(3 * 3600 + 53 * 60), windowLength: nil)
        XCTAssertEqual(PaceFormatter.resetLabel(for: lane, now: now), "resets in 3h 53m")
    }

    func testProjectionLabel() {
        let resetDate = Date(timeIntervalSince1970: 10 * 3600)
        let capDate = resetDate.addingTimeInterval(-2 * 3600)
        XCTAssertEqual(PaceFormatter.projectionLabel(capDate: capDate, resetDate: resetDate), "~2h before reset")
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PaceCalculatorTests`
Expected: FAIL — `PaceCalculator`/`PaceFormatter` not found.

- [ ] **Step 3: Implement**

`Sources/PaceCore/PaceCalculator.swift`:

```swift
import Foundation

public enum PaceCalculator {
    public static func reading(for lane: LaneUsage, now: Date) -> PaceReading {
        guard let windowLength = lane.windowLength, windowLength > 0 else {
            return PaceReading(lane: lane, percentElapsed: nil, isAheadOfPace: false, projectedCapDate: nil)
        }

        let windowStart = lane.resetDate.addingTimeInterval(-windowLength)
        let elapsed = max(0, min(now.timeIntervalSince(windowStart), windowLength))
        let percentElapsed = Int((elapsed / windowLength) * 100)
        let ahead = lane.percentUsed > percentElapsed

        var projectedCapDate: Date? = nil
        if ahead, elapsed > 0, lane.percentUsed > 0 {
            let ratePerSecond = Double(lane.percentUsed) / elapsed
            let secondsTo100 = 100.0 / ratePerSecond
            projectedCapDate = windowStart.addingTimeInterval(secondsTo100)
        }

        return PaceReading(lane: lane, percentElapsed: percentElapsed, isAheadOfPace: ahead, projectedCapDate: projectedCapDate)
    }
}
```

`Sources/PaceCore/PaceFormatter.swift`:

```swift
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

    public static func projectionLabel(capDate: Date, resetDate: Date) -> String {
        let hours = max(0, Int(resetDate.timeIntervalSince(capDate)) / 3600)
        return hours <= 0 ? "before reset" : "~\(hours)h before reset"
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter PaceCalculatorTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PaceCore/PaceCalculator.swift Sources/PaceCore/PaceFormatter.swift Tests/PaceCoreTests/PaceCalculatorTests.swift
git commit -m "feat: add PaceCalculator and PaceFormatter"
```

---

## Task 5: IconGeometry — pure bar geometry for the icon

**Files:**
- Create: `Sources/PaceCore/IconGeometry.swift`
- Test: `Tests/PaceCoreTests/IconGeometryTests.swift`

**Interfaces:**
- Consumes: `PaceReading` (Task 2/4).
- Produces: `BarGeometry` (`fillFraction: Double`, `tickFraction: Double?`, `isHot: Bool`), `IconGeometry.barGeometry(for:) -> BarGeometry` — consumed by Task 10 (`IconRenderer`).

- [ ] **Step 1: Write the test**

`Tests/PaceCoreTests/IconGeometryTests.swift`:

```swift
import XCTest
@testable import PaceCore

final class IconGeometryTests: XCTestCase {
    func testGeometryWithKnownWindow() {
        let lane = LaneUsage(kind: .fableWeek, percentUsed: 45, resetDate: Date(), windowLength: 7 * 24 * 3600)
        let reading = PaceReading(lane: lane, percentElapsed: 47, isAheadOfPace: false, projectedCapDate: nil)
        let geo = IconGeometry.barGeometry(for: reading)
        XCTAssertEqual(geo.fillFraction, 0.45, accuracy: 0.001)
        XCTAssertEqual(geo.tickFraction, 0.47, accuracy: 0.001)
        XCTAssertFalse(geo.isHot)
    }

    func testGeometryWithUnknownWindow() {
        let lane = LaneUsage(kind: .session, percentUsed: 70, resetDate: Date(), windowLength: nil)
        let reading = PaceReading(lane: lane, percentElapsed: nil, isAheadOfPace: false, projectedCapDate: nil)
        let geo = IconGeometry.barGeometry(for: reading)
        XCTAssertEqual(geo.fillFraction, 0.70, accuracy: 0.001)
        XCTAssertNil(geo.tickFraction)
    }

    func testGeometryMarksHotWhenAheadOfPace() {
        let lane = LaneUsage(kind: .session, percentUsed: 70, resetDate: Date(), windowLength: 5 * 3600)
        let reading = PaceReading(lane: lane, percentElapsed: 40, isAheadOfPace: true, projectedCapDate: Date())
        let geo = IconGeometry.barGeometry(for: reading)
        XCTAssertTrue(geo.isHot)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter IconGeometryTests`
Expected: FAIL — `IconGeometry`/`BarGeometry` not found.

- [ ] **Step 3: Implement**

`Sources/PaceCore/IconGeometry.swift`:

```swift
public struct BarGeometry: Equatable, Sendable {
    public let fillFraction: Double
    public let tickFraction: Double?
    public let isHot: Bool

    public init(fillFraction: Double, tickFraction: Double?, isHot: Bool) {
        self.fillFraction = fillFraction
        self.tickFraction = tickFraction
        self.isHot = isHot
    }
}

public enum IconGeometry {
    public static func barGeometry(for reading: PaceReading) -> BarGeometry {
        BarGeometry(
            fillFraction: Double(reading.lane.percentUsed) / 100.0,
            tickFraction: reading.percentElapsed.map { Double($0) / 100.0 },
            isHot: reading.isAheadOfPace
        )
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter IconGeometryTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PaceCore/IconGeometry.swift Tests/PaceCoreTests/IconGeometryTests.swift
git commit -m "feat: add IconGeometry for icon bar rendering"
```

---

## Task 6: Confirm live navigation path and capture real panel text (manual research)

This is not a code task. Its job is to close the two real unknowns flagged in the spec and in Task 3/7's notes: (1) the exact click path to reach Settings → Usage reliably from code (design-time research confirmed profile-avatar → "Settings" → "Usage", but did not pin down a codeable selector for the profile-avatar button), and (2) the current-session window's total length.

**Files:**
- Create: `docs/superpowers/research/live-usage-page-notes.md`

- [ ] **Step 1: Reproduce the manual navigation**

Open claude.ai in a real logged-in browser. Click the profile avatar button (bottom of the left sidebar), then "Settings", then the "Usage" tab. Confirm this still matches the path used during design research.

- [ ] **Step 2: Capture a codeable way to find the profile-avatar button**

Using Safari Web Inspector (or the claude-in-chrome extension), inspect the profile avatar button's DOM node. Record something Task 8's JS can reliably match on — an `aria-label`, a stable `data-testid`, or (if nothing stable exists) its structural position (e.g. "last button in the `<nav>` element"). Do not rely on generated class names (e.g. `css-1a2b3c`) — those are expected to change across deploys.

- [ ] **Step 3: Capture the real panel text**

With the Usage tab open, run `document.body.innerText` (or the narrowest container that wraps just the three usage lanes) in the console. Save the verbatim output.

- [ ] **Step 4: Determine the session window length**

Note the wall-clock time and the exact "Resets in Xh Ym" value. Repeat the observation at least a few hours later (ideally spanning an actual session reset, where the countdown jumps back up to its maximum). The difference between two countdowns plus the elapsed wall-clock time between observations gives the window length. If Anthropic documents this value directly (check support docs), record that as the source instead and skip the multi-observation method.

- [ ] **Step 5: Write findings**

`docs/superpowers/research/live-usage-page-notes.md` — include: the confirmed avatar-button lookup from Step 2, the verbatim captured text from Step 3, and either the confirmed session window length (with source/method) or an explicit note that it's still unconfirmed and Task 9 must keep passing `nil`.

- [ ] **Step 6: Reconcile Task 3's fixtures**

Compare the captured text from Step 3 against the fixture strings used in `Tests/PaceCoreTests/UsageParserTests.swift` and the sample panel text planned for Task 7. If the real format differs (spacing, wording, "hr" vs "hrs", etc.), update those regexes/fixtures now and re-run `swift test` before moving on.

- [ ] **Step 7: Commit**

```bash
git add docs/superpowers/research/live-usage-page-notes.md
git commit -m "docs: capture live claude.ai usage panel findings"
```

---

## Task 7: UsagePanelTextExtractor — split scraped text into lanes

**Files:**
- Create: `Sources/PaceCore/UsagePanelTextExtractor.swift`
- Test: `Tests/PaceCoreTests/UsagePanelTextExtractorTests.swift`

**Interfaces:**
- Consumes: `UsageParser` (Task 3), `LaneUsage`/`LaneKind` (Task 2).
- Produces: `UsagePanelTextExtractor.extractLanes(from:now:sessionWindowLength:) -> [LaneUsage]?` — consumed by Task 8 (`UsageFetcher`).

**Note:** the fixture text below is reconstructed from the design screenshots, same caveat as Task 3 — reconcile against Task 6's real capture if the format differs before trusting this in Task 8.

- [ ] **Step 1: Write the test**

`Tests/PaceCoreTests/UsagePanelTextExtractorTests.swift`:

```swift
import XCTest
@testable import PaceCore

final class UsagePanelTextExtractorTests: XCTestCase {
    let sample = """
    Plan usage limits Max (5x)

    Current session
    Resets in 3 hr 53 min
    21% used

    Weekly limits
    Fable 5 is still included with your Max plan.

    All models
    Resets Sat 2:00 PM
    16% used

    Fable
    Resets Sat 2:00 PM
    21% used
    """

    func testExtractsAllThreeLanes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 18, hour: 12))!

        let lanes = UsagePanelTextExtractor.extractLanes(from: sample, now: now, sessionWindowLength: nil)

        XCTAssertNotNil(lanes)
        guard let lanes else { return }
        XCTAssertEqual(lanes.count, 3)

        let session = lanes.first { $0.kind == .session }
        XCTAssertEqual(session?.percentUsed, 21)
        XCTAssertNil(session?.windowLength)

        let allModels = lanes.first { $0.kind == .allModelsWeek }
        XCTAssertEqual(allModels?.percentUsed, 16)
        XCTAssertEqual(allModels?.windowLength, 7 * 24 * 3600)

        let fable = lanes.first { $0.kind == .fableWeek }
        XCTAssertEqual(fable?.percentUsed, 21)
    }

    func testReturnsNilWhenAnchorMissing() {
        let broken = "Current session\nResets in 3 hr 53 min\n21% used"
        XCTAssertNil(UsagePanelTextExtractor.extractLanes(from: broken, now: Date(), sessionWindowLength: nil))
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter UsagePanelTextExtractorTests`
Expected: FAIL — `UsagePanelTextExtractor` not found.

- [ ] **Step 3: Implement**

`Sources/PaceCore/UsagePanelTextExtractor.swift`:

```swift
import Foundation

public enum UsagePanelTextExtractor {
    private static let laneAnchors: [(LaneKind, String)] = [
        (.session, "Current session"),
        (.allModelsWeek, "All models"),
        (.fableWeek, "Fable")
    ]

    public static func extractLanes(from panelText: String, now: Date, sessionWindowLength: TimeInterval?) -> [LaneUsage]? {
        let found = laneAnchors.compactMap { kind, anchor -> (LaneKind, Range<String.Index>)? in
            panelText.range(of: anchor).map { (kind, $0) }
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter UsagePanelTextExtractorTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/PaceCore/UsagePanelTextExtractor.swift Tests/PaceCoreTests/UsagePanelTextExtractorTests.swift
git commit -m "feat: add UsagePanelTextExtractor"
```

---

## Task 8: UsageFetcher — hidden WKWebView scraper

**Files:**
- Create: `Sources/Pace/UsageFetcher.swift`

**Interfaces:**
- Consumes: `UsagePanelTextExtractor`, `LaneUsage`, `FetchStatus` (PaceCore).
- Produces: `UsageFetcherDelegate` protocol (`usageFetcher(_:didProduce:)`, `usageFetcher(_:didFailWith:)`), `UsageFetcher` (`delegate`, `refresh() async`, `presentLoginWindow()`, `clearSession() async`) — consumed by Task 9 (`AppState`).

This task has no unit tests — it drives a real `WKWebView` against the live internet, which isn't something to fake with fixtures. It's verified manually in Task 15. Before writing the click-path code, re-read `docs/superpowers/research/live-usage-page-notes.md` from Task 6 and use whatever avatar-button lookup it confirmed — the lookup below is a starting point, not a substitute for that.

- [ ] **Step 1: Implement**

`Sources/Pace/UsageFetcher.swift`:

```swift
import Foundation
import WebKit
import PaceCore

protocol UsageFetcherDelegate: AnyObject {
    func usageFetcher(_ fetcher: UsageFetcher, didProduce lanes: [LaneUsage])
    func usageFetcher(_ fetcher: UsageFetcher, didFailWith status: FetchStatus)
}

/// Session window length for the "Current session" lane, once confirmed by
/// Task 6's live research. Stays `nil` (no pace tick/projection for that
/// lane) until then — see Global Constraints.
enum SessionWindow {
    static let confirmedLength: TimeInterval? = nil
}

@MainActor
final class UsageFetcher: NSObject {
    weak var delegate: UsageFetcherDelegate?

    private let webView: WKWebView
    private let window: NSWindow

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: config)
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Pace — Sign in to claude.ai"
        window.contentView = webView
        window.setIsVisible(false)
        super.init()
    }

    func refresh() async {
        guard let url = URL(string: "https://claude.ai/new") else { return }
        webView.load(URLRequest(url: url))
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        guard await clickThroughToUsagePanel() else {
            delegate?.usageFetcher(self, didFailWith: .needsLogin)
            return
        }

        guard let panelText = await readUsagePanelText(), !panelText.isEmpty else {
            delegate?.usageFetcher(self, didFailWith: .parseError("Usage panel text not found"))
            return
        }

        guard let lanes = UsagePanelTextExtractor.extractLanes(
            from: panelText, now: Date(), sessionWindowLength: SessionWindow.confirmedLength
        ) else {
            delegate?.usageFetcher(self, didFailWith: .parseError("Could not parse usage panel text"))
            return
        }

        delegate?.usageFetcher(self, didProduce: lanes)
    }

    func presentLoginWindow() {
        window.setIsVisible(true)
        window.makeKeyAndOrderFront(nil)
    }

    func clearSession() async {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        await webView.configuration.websiteDataStore.removeData(ofTypes: types, modifiedSince: .distantPast)
    }

    /// Starting point confirmed against Task 6's findings — the avatar-button
    /// match in particular MUST use whatever lookup Task 6 documented, not
    /// necessarily the placeholder text-match below.
    private func clickThroughToUsagePanel() async -> Bool {
        let openSettingsScript = """
        (function() {
          function clickButtonContaining(txt) {
            const btns = Array.from(document.querySelectorAll('button'));
            const match = btns.find(b => b.textContent && b.textContent.trim().includes(txt));
            if (match) { match.click(); return true; }
            return false;
          }
          // Task 6 must confirm the real avatar-button lookup and this call
          // site should use it before this counts as done.
          const avatarOpened = clickButtonContaining('Ryan');
          return avatarOpened;
        })();
        """
        let avatarOpened = (try? await webView.evaluateJavaScript(openSettingsScript) as? Bool) ?? false
        guard avatarOpened else { return false }
        try? await Task.sleep(nanoseconds: 500_000_000)

        let settingsScript = """
        (function() {
          const btns = Array.from(document.querySelectorAll('button'));
          const match = btns.find(b => b.textContent && b.textContent.trim() === 'Settings');
          if (match) { match.click(); return true; }
          return false;
        })();
        """
        _ = try? await webView.evaluateJavaScript(settingsScript)
        try? await Task.sleep(nanoseconds: 500_000_000)

        let usageScript = """
        (function() {
          const btns = Array.from(document.querySelectorAll('button'));
          const match = btns.find(b => b.textContent && b.textContent.trim() === 'Usage');
          if (match) { match.click(); return true; }
          return false;
        })();
        """
        let usageOpened = (try? await webView.evaluateJavaScript(usageScript) as? Bool) ?? false
        try? await Task.sleep(nanoseconds: 500_000_000)
        return usageOpened
    }

    private func readUsagePanelText() async -> String? {
        try? await webView.evaluateJavaScript("document.body.innerText") as? String
    }
}
```

- [ ] **Step 2: Verify the target builds**

Run: `swift build`
Expected: succeeds with no errors (the `main-placeholder.swift` entry point from Task 1 is still in place; this task adds a class nothing calls yet).

- [ ] **Step 3: Commit**

```bash
git add Sources/Pace/UsageFetcher.swift
git commit -m "feat: add UsageFetcher WKWebView scraper"
```

---

## Task 9: AppState — timer-driven fetch orchestration

**Files:**
- Create: `Sources/Pace/AppState.swift`

**Interfaces:**
- Consumes: `UsageFetcher`, `UsageFetcherDelegate` (Task 8), `PaceCalculator` (Task 4), `PaceReading`, `FetchStatus` (Task 2/4).
- Produces: `AppState` (`paceReadings: [PaceReading]`, `status: FetchStatus`, `lastSuccessAt: Date?`, `refreshInterval: TimeInterval`, `lastSuccessLabel: String`, `startTimer()`, `refreshNow()`, `presentLogin()`, `openClaudeUsagePage()`, `signOut()`) — consumed by Task 11 (`MenuView`), Task 12 (`PaceApp`), Task 13 (`PreferencesView`).

No unit tests here — this is Timer/async orchestration glue over `UsageFetcher`, which itself has no fixtures (Task 8). Verified manually in Task 15 alongside the fetcher.

- [ ] **Step 1: Implement**

`Sources/Pace/AppState.swift`:

```swift
import Foundation
import AppKit
import Observation
import PaceCore

@Observable
@MainActor
final class AppState {
    private(set) var paceReadings: [PaceReading] = []
    private(set) var status: FetchStatus = .needsLogin
    private(set) var lastSuccessAt: Date?
    var refreshInterval: TimeInterval = 360 // 6 minutes — Global Constraints default

    private let fetcher: UsageFetcher
    private var timer: Timer?

    init(fetcher: UsageFetcher = UsageFetcher()) {
        self.fetcher = fetcher
        fetcher.delegate = self
        startTimer()
        refreshNow()
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshNow() }
        }
    }

    func refreshNow() {
        Task { await fetcher.refresh() }
    }

    func presentLogin() {
        fetcher.presentLoginWindow()
    }

    func openClaudeUsagePage() {
        NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
    }

    func signOut() {
        Task {
            await fetcher.clearSession()
            status = .needsLogin
        }
    }

    var lastSuccessLabel: String {
        guard let lastSuccessAt else { return "not yet updated" }
        let minutes = max(0, Int(Date().timeIntervalSince(lastSuccessAt)) / 60)
        return minutes == 0 ? "updated just now" : "updated \(minutes)m ago"
    }
}

extension AppState: UsageFetcherDelegate {
    nonisolated func usageFetcher(_ fetcher: UsageFetcher, didProduce lanes: [LaneUsage]) {
        Task { @MainActor in
            self.paceReadings = lanes.map { PaceCalculator.reading(for: $0, now: Date()) }
            self.status = .ok
            self.lastSuccessAt = Date()
        }
    }

    nonisolated func usageFetcher(_ fetcher: UsageFetcher, didFailWith status: FetchStatus) {
        Task { @MainActor in
            self.status = status
            // paceReadings intentionally left as the last-known values.
        }
    }
}
```

- [ ] **Step 2: Verify the target builds**

Run: `swift build`
Expected: succeeds. If the compiler flags anything about `nonisolated`/`@MainActor` isolation on the `UsageFetcherDelegate` conformance below, that's real Swift concurrency-checking output to resolve here, not a sign the approach is wrong — adjust the isolation annotations until it's clean.

- [ ] **Step 3: Commit**

```bash
git add Sources/Pace/AppState.swift
git commit -m "feat: add AppState timer-driven fetch orchestration"
```

---

## Task 10: IconRenderer — draws the menu bar icon

**Files:**
- Create: `Sources/Pace/IconRenderer.swift`

**Interfaces:**
- Consumes: `IconGeometry`, `BarGeometry`, `PaceReading`, `FetchStatus` (PaceCore).
- Produces: `IconRenderer.render(readings:status:) -> NSImage` — consumed by Task 12 (`PaceApp`).

No automated test — per the spec, icon pixels are checked by eye, not asserted on. Verified by running the app in Task 15 and by the manual preview in Step 2 below.

- [ ] **Step 1: Implement**

`Sources/Pace/IconRenderer.swift`:

```swift
import AppKit
import PaceCore

enum IconRenderer {
    static func render(readings: [PaceReading], status: FetchStatus) -> NSImage {
        let geometries = readings.map(IconGeometry.barGeometry(for:))
        let width: CGFloat = 22
        let height: CGFloat = 16
        let image = NSImage(size: NSSize(width: width, height: height))

        let isStale: Bool
        switch status {
        case .ok: isStale = false
        case .needsLogin, .parseError: isStale = true
        }
        let hasHotLane = geometries.contains { $0.isHot }

        image.lockFocus()
        NSGraphicsContext.current?.cgContext.setAlpha(isStale ? 0.45 : 1.0)

        let laneHeight: CGFloat = 3
        let gap: CGFloat = 2.5
        for (index, geo) in geometries.enumerated() {
            let y = CGFloat(index) * (laneHeight + gap) + 1
            let trackRect = NSRect(x: 0, y: y, width: width, height: laneHeight)
            NSColor(white: 0.29, alpha: 1).setFill()
            NSBezierPath(roundedRect: trackRect, xRadius: 1, yRadius: 1).fill()

            let fillWidth = width * CGFloat(geo.fillFraction)
            let fillRect = NSRect(x: 0, y: y, width: fillWidth, height: laneHeight)
            (geo.isHot ? NSColor.systemRed : NSColor(white: 0.95, alpha: 1)).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1).fill()

            if let tick = geo.tickFraction {
                let tickX = width * CGFloat(tick)
                NSColor.black.withAlphaComponent(0.6)
                    .setFill()
                NSRect(x: tickX, y: y - 1, width: 1, height: laneHeight + 2).fill()
            }
        }

        if isStale {
            let badge = NSRect(x: width - 5, y: height - 5, width: 4, height: 4)
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: badge).fill()
        }

        image.unlockFocus()
        image.isTemplate = !isStale && !hasHotLane
        return image
    }
}
```

- [ ] **Step 2: Manual visual check**

Run: `swift build && swift run Pace` is not yet wired to call this (Task 12 does that) — for now, verify it compiles with `swift build`. The real look is checked once Task 12 wires it into the actual status item; adjust the drawing constants there if it doesn't read cleanly at real menu bar size.

- [ ] **Step 3: Commit**

```bash
git add Sources/Pace/IconRenderer.swift
git commit -m "feat: add IconRenderer for the menu bar icon"
```

---

## Task 11: MenuView — the dropdown

**Files:**
- Create: `Sources/Pace/MenuView.swift`

**Interfaces:**
- Consumes: `AppState` (Task 9), `PaceReading`, `PaceFormatter` (PaceCore).
- Produces: `MenuView` (SwiftUI `View`) — consumed by Task 12 (`PaceApp`).

- [ ] **Step 1: Implement**

`Sources/Pace/MenuView.swift`:

```swift
import SwiftUI
import PaceCore

struct MenuView: View {
    @Bindable var appState: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Claude Usage")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)

            ForEach(appState.paceReadings, id: \.lane.kind) { reading in
                LaneRow(reading: reading)
                Divider()
            }

            statusRow

            Divider()
            MenuActionRow(title: "Refresh now", hint: appState.lastSuccessLabel) { appState.refreshNow() }
            MenuActionRow(title: "Open claude.ai usage", hint: nil) { appState.openClaudeUsagePage() }
            MenuActionRow(title: "Preferences…", hint: nil) { openSettings() }
            MenuActionRow(title: "Quit", hint: nil) { NSApplication.shared.terminate(nil) }
        }
        .frame(width: 300)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var statusRow: some View {
        switch appState.status {
        case .needsLogin:
            Button("Sign in to claude.ai") { appState.presentLogin() }
                .buttonStyle(.plain)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .parseError(let detail):
            Text("Couldn't refresh usage (\(detail)). Showing last known values.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
        case .ok:
            EmptyView()
        }
    }
}

private struct LaneRow: View {
    let reading: PaceReading

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(reading.lane.kind.displayName).font(.system(size: 12.5)).foregroundStyle(.secondary)
                Spacer()
                Text("\(reading.lane.percentUsed)%")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(reading.isAheadOfPace ? Color.red : Color.primary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.3))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(reading.isAheadOfPace ? Color.red : Color(white: 0.85))
                        .frame(width: geo.size.width * CGFloat(reading.lane.percentUsed) / 100)
                    if let percentElapsed = reading.percentElapsed {
                        Rectangle().fill(Color.white.opacity(0.9))
                            .frame(width: 2)
                            .offset(x: geo.size.width * CGFloat(percentElapsed) / 100)
                    }
                }
            }
            .frame(height: 5)

            HStack {
                Text(PaceFormatter.resetLabel(for: reading.lane, now: Date()))
                Spacer()
                if let percentElapsed = reading.percentElapsed {
                    Text("\(percentElapsed)% of window elapsed")
                }
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)

            if reading.isAheadOfPace, let capDate = reading.projectedCapDate {
                Text("Projected to hit cap \(PaceFormatter.projectionLabel(capDate: capDate, resetDate: reading.lane.resetDate))")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

private struct MenuActionRow: View {
    let title: String
    let hint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 12.5))
                Spacer()
                if let hint { Text(hint).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
```

- [ ] **Step 2: Verify the target builds**

Run: `swift build`
Expected: succeeds (nothing calls `MenuView` yet — that's Task 12).

- [ ] **Step 3: Commit**

```bash
git add Sources/Pace/MenuView.swift
git commit -m "feat: add MenuView dropdown"
```

---

## Task 12: PaceApp — wire everything together

**Files:**
- Create: `Sources/Pace/PaceApp.swift`
- Delete: `Sources/Pace/main-placeholder.swift`

**Interfaces:**
- Consumes: `AppState` (Task 9), `IconRenderer` (Task 10), `MenuView` (Task 11).
- Produces: the app entry point — nothing later depends on this except the build itself.

- [ ] **Step 1: Implement**

`Sources/Pace/PaceApp.swift`:

```swift
import SwiftUI

@main
struct PaceApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuView(appState: appState)
        } label: {
            Image(nsImage: IconRenderer.render(readings: appState.paceReadings, status: appState.status))
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(appState: appState)
        }
    }
}
```

- [ ] **Step 2: Remove the placeholder entry point**

```bash
git rm Sources/Pace/main-placeholder.swift
```

- [ ] **Step 3: Verify the target builds**

Run: `swift build`
Expected: fails until Task 13 adds `PreferencesView` — that's expected and resolved next. If you're executing tasks strictly in order, this step is a checkpoint to confirm the error is exactly "cannot find 'PreferencesView' in scope" and nothing else.

- [ ] **Step 4: Commit**

```bash
git add Sources/Pace/PaceApp.swift
git commit -m "feat: add PaceApp entry point (depends on Task 13's PreferencesView)"
```

---

## Task 13: PreferencesView + launch-at-login

**Files:**
- Create: `Sources/Pace/PreferencesView.swift`

**Interfaces:**
- Consumes: `AppState` (Task 9), `ServiceManagement.SMAppService`.
- Produces: `PreferencesView` (SwiftUI `View`) — consumed by Task 12 (`PaceApp`), closing the gap left there.

- [ ] **Step 1: Implement**

`Sources/Pace/PreferencesView.swift`:

```swift
import SwiftUI
import ServiceManagement

struct PreferencesView: View {
    @Bindable var appState: AppState
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Stepper(value: $appState.refreshInterval, in: 60...1800, step: 60) {
                Text("Refresh every \(Int(appState.refreshInterval / 60)) min")
            }
            .onChange(of: appState.refreshInterval) { _, _ in appState.startTimer() }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }

            Button("Sign out of claude.ai") { appState.signOut() }
        }
        .padding(20)
        .frame(width: 320)
    }
}
```

- [ ] **Step 2: Verify the full app target builds**

Run: `swift build`
Expected: succeeds — this closes the gap left by Task 12.

- [ ] **Step 3: Commit**

```bash
git add Sources/Pace/PreferencesView.swift
git commit -m "feat: add PreferencesView with launch-at-login"
```

---

## Task 14: App bundle packaging

**Files:**
- Modify: `Scripts/build-app.sh` (verify against the real build output)
- Modify: `Sources/Pace/Info.plist` (bump version if needed)

**Interfaces:**
- Consumes: the release build produced by `swift build -c release` (Task 1's Makefile).
- Produces: `.build/Pace.app`, `~/Applications/Pace.app` (via `make install`).

- [ ] **Step 1: Build and package**

Run: `make app`
Expected: `.build/Pace.app` exists, `codesign -dv .build/Pace.app` shows an ad-hoc signature with no errors.

- [ ] **Step 2: Confirm the bundle actually launches**

Run: `open .build/Pace.app`
Expected: a status item appears in the menu bar (no Dock icon, since `LSUIElement` is `true`); clicking it opens the dropdown.

- [ ] **Step 3: Install and verify launch-at-login registration**

Run: `make install`, then open `~/Applications/Pace.app`, open Preferences, toggle "Launch at login" on, and confirm via `sfltool dumpbtm | grep -A2 com.sternryan.pace` (or System Settings → General → Login Items) that it registered.

- [ ] **Step 4: Commit any script fixes made while packaging**

```bash
git add Scripts/build-app.sh Sources/Pace/Info.plist
git commit -m "chore: verify app packaging and launch-at-login registration"
```

(Skip the commit if Steps 1–3 needed no changes.)

---

## Task 15: Manual end-to-end verification

Not a code task — this is the live verification the spec calls for, since the scrape can't be fixture-tested. Do not consider Pace "done" until every item below is checked against your real account, per the project's verification rule.

- [ ] **Step 1: Sign-in flow** — launch `Pace.app` fresh (no prior session). Confirm the icon shows the dimmed/stale state, opening the dropdown offers "Sign in to claude.ai", and completing sign-in in the presented window results in the icon populating with real data within one refresh cycle.

- [ ] **Step 2: Numbers match reality** — open claude.ai's Settings → Usage in a normal browser tab at the same moment. Confirm all three lanes' percentages and reset times in Pace's dropdown match what claude.ai shows.

- [ ] **Step 3: Pace math sanity check** — by hand, compute % of window elapsed for the two weekly lanes (you know their 7-day cadence) and confirm it matches Pace's dropdown. For the session lane, confirm Pace shows "no tick" behavior if `SessionWindow.confirmedLength` is still `nil`, or correct pace math if Task 6 confirmed a value.

- [ ] **Step 4: Hot-lane behavior** — either wait for a real ahead-of-pace lane, or temporarily hardcode a `LaneUsage` in `AppState.init` with `percentUsed` deliberately higher than its elapsed-time percentage, rebuild, and confirm: the icon's corresponding bar turns red (and only that bar), the dropdown shows the red "Projected to hit cap" line, and the projection date is before the reset date. Revert the temporary hardcode afterward.

- [ ] **Step 5: Failure states** — quit Pace, disable Wi-Fi, relaunch. Confirm the icon shows last-known values dimmed with the ‼ badge (or, on true first-launch-with-no-network, a clearly non-crashing empty state) and the dropdown explains what happened. Re-enable Wi-Fi and confirm the next timer tick recovers to `.ok`.

- [ ] **Step 6: Refresh cadence** — leave Pace running and confirm "updated Xm ago" in the dropdown advances and resets roughly every 6 minutes without manual refresh.

- [ ] **Step 7: Launch at login persists across reboot** — with the toggle on, reboot the Mac and confirm Pace is running afterward without manual intervention.

- [ ] **Step 8: Record the outcome**

If every step above passes, this plan is complete. If anything doesn't match, fix it, note what was wrong and why in the commit message, and re-run the affected steps before calling it done — per the project's "nothing is done until verified end-to-end" rule, this task is the actual gate, not the earlier unit tests.
