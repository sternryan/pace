import AppKit
import PaceCore

enum IconRenderer {
    /// Draws the pinned lane as a mini progress bar plus its percent, in the
    /// menubar's monochrome style — red only when the lane is ahead of pace
    /// or capped (repo rule: "red is the only color the icon may ever
    /// show"), dimmed grey when the report is stale, and a bare dash when
    /// there's no data yet (e.g. before the first successful fetch).
    static func image(for pinned: WindowVerdict?, stale: Bool) -> NSImage {
        let width: CGFloat = 34
        let height: CGFloat = 16
        let image = NSImage(size: NSSize(width: width, height: height))

        let isHot = pinned.map { $0.status == .ahead || $0.status == .capped } ?? false

        image.lockFocus()
        NSGraphicsContext.current?.cgContext.setAlpha(stale ? 0.45 : 1.0)

        let barWidth: CGFloat = 18
        let barHeight: CGFloat = 4
        let barY = (height - barHeight) / 2
        let trackRect = NSRect(x: 0, y: barY, width: barWidth, height: barHeight)
        NSColor.tertiaryLabelColor.setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: 1, yRadius: 1).fill()

        if let pinned {
            let fillWidth = barWidth * CGFloat(min(max(pinned.percentUsed, 0), 100)) / 100
            let fillRect = NSRect(x: 0, y: barY, width: fillWidth, height: barHeight)
            (isHot ? NSColor.systemRed : NSColor.labelColor).setFill()
            NSBezierPath(roundedRect: fillRect, xRadius: 1, yRadius: 1).fill()

            if let elapsed = pinned.percentElapsed {
                let tickX = barWidth * CGFloat(elapsed) / 100
                NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
                NSRect(x: tickX, y: barY - 1, width: 1, height: barHeight + 2).fill()
            }
        }

        let text = pinned.map { "\(min(max($0.percentUsed, 0), 100))%" } ?? "–"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let color = isHot ? NSColor.systemRed : NSColor.labelColor
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let string = NSAttributedString(string: text, attributes: attrs)
        let textSize = string.size()
        let textRect = NSRect(x: barWidth + 3, y: (height - textSize.height) / 2, width: width - barWidth - 3, height: textSize.height)
        string.draw(in: textRect)

        image.unlockFocus()
        image.isTemplate = !stale && !isHot
        return image
    }
}
