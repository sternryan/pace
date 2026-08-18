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
            // Top-to-bottom in the icon must match the dropdown's list order
            // (session, all-models week, Fable week) — the dropdown renders
            // index 0 first/topmost, so the icon draws index 0 at the highest
            // y here to line the two views up consistently.
            let y = CGFloat(geometries.count - 1 - index) * (laneHeight + gap) + 1
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
            // Use a fixed small corner rect (not derived from font metrics) to avoid
            // line-height inflation pushing the glyph into lanes. 6pt font keeps
            // visible ink ~3-4pt; when drawn in a 5pt-tall rect at y 11-16, ink
            // stays mostly above lane 2 (y 12-15) with only minimal edge overlap.
            let glyph = "‼"
            let badgeFont = NSFont.systemFont(ofSize: 6, weight: .semibold)
            let badgeAttrs: [NSAttributedString.Key: Any] = [
                .font: badgeFont,
                .foregroundColor: NSColor.labelColor
            ]
            let badgeString = NSAttributedString(string: glyph, attributes: badgeAttrs)
            // Fixed rect in top-right corner: x 17-22, y 11-16 (same area as original badge)
            let badgeRect = NSRect(x: width - 5, y: height - 5, width: 5, height: 5)
            badgeString.draw(in: badgeRect)
        }

        image.unlockFocus()
        image.isTemplate = !isStale && !hasHotLane
        return image
    }
}
