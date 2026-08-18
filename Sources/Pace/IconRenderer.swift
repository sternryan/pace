import AppKit
import PaceCore

enum IconRenderer {
    static func render(readings: [PaceReading], status: FetchStatus) -> NSImage {
        // Before the first successful fetch, readings is empty. Draw 3 empty
        // tracks (no fill, no fake numbers) rather than nothing — the spec's
        // "never blank the icon" invariant applies to first launch too, not
        // just post-fetch failure states (review finding, cross-model).
        let geometries = readings.isEmpty
            ? Array(repeating: BarGeometry(fillFraction: 0, tickFraction: nil, isHot: false), count: 3)
            : readings.map(IconGeometry.barGeometry(for:))
        let width: CGFloat = 22
        let height: CGFloat = 16
        let image = NSImage(size: NSSize(width: width, height: height))

        let isStale: Bool
        switch status {
        case .ok: isStale = false
        case .needsLogin, .navigationFailed, .parseError: isStale = true
        }
        let hasHotLane = geometries.contains { $0.isHot }

        image.lockFocus()
        NSGraphicsContext.current?.cgContext.setAlpha(isStale ? 0.45 : 1.0)

        let laneHeight: CGFloat = 3
        let gap: CGFloat = 2.5
        // labelColor/secondaryLabelColor are appearance-aware (resolve to
        // black in light mode, white in dark mode) — used instead of
        // hardcoded white/grey so non-hot bars stay legible even when the
        // whole image can't be template mode (the hot bar needs literal
        // red). Hardcoded values would go fixed-near-white and vanish
        // against a light menu bar — review finding, cross-model.
        for (index, geo) in geometries.enumerated() {
            let y = CGFloat(index) * (laneHeight + gap) + 1
            let trackRect = NSRect(x: 0, y: y, width: width, height: laneHeight)
            NSColor.tertiaryLabelColor.setFill()
            NSBezierPath(roundedRect: trackRect, xRadius: 1, yRadius: 1).fill()

            let fillWidth = width * CGFloat(geo.fillFraction)
            let fillRect = NSRect(x: 0, y: y, width: fillWidth, height: laneHeight)
            (geo.isHot ? NSColor.systemRed : NSColor.labelColor).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1).fill()

            if let tick = geo.tickFraction {
                let tickX = width * CGFloat(tick)
                // windowBackgroundColor punches a visible gap against the
                // labelColor/red fill in both appearances — hardcoded black
                // would vanish in dark mode (same bug class as above).
                NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
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
