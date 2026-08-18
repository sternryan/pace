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
            // Draw a "‼" glyph to indicate stale state, using labelColor
            // (appearance-aware, template-safe) — never systemRed, which
            // must be reserved for ahead-of-pace lane fills only (spec: "the
            // only color ever shown is red, and only on a lane that is ahead
            // of pace"). The glyph inherits the alpha dimming (0.45) from the
            // lockFocus context set above — whole stale treatment dims as one unit.
            // Positioned in top-right corner, clear of all 3 lanes (which occupy y 1–15).
            let glyph = "‼"
            let badgeFont = NSFont.systemFont(ofSize: 9, weight: .semibold)
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: NSColor.labelColor
            ]
            let badgeString = NSAttributedString(string: glyph, attributes: badgeAttrs)
            let badgeSize = badgeString.size()
            // Position in top-right corner with 1pt padding from edges
            let badgeRect = NSRect(x: width - badgeSize.width - 1, y: height - badgeSize.height - 1, width: badgeSize.width, height: badgeSize.height)
            badgeString.draw(in: badgeRect)
        }

        image.unlockFocus()
        image.isTemplate = !isStale && !hasHotLane
        return image
    }
}
