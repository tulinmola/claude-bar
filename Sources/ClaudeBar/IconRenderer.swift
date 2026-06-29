import AppKit

enum IconRenderer {
    static let size = NSSize(width: 28, height: 18)
    private static let barHeight: CGFloat = 3.5
    private static let weeklyY: CGFloat = 0
    private static let sessionY: CGFloat = 5

    /// How many points of cushion before the time line at which the bar turns
    /// from green (comfortable) to yellow (approaching the line).
    private static let paceWarnMargin: Double = 10

    /// A tiny "Claude" label over two battery-style horizontal bars — Session
    /// (5h) on top, Weekly (7d) below. Bar length is how much you've spent; a
    /// thin vertical line marks how far into the window we are; and the color is
    /// the pace between them — green with a comfortable cushion, yellow nearing
    /// the line, red once the fill passes it. Colors adapt to the menu bar
    /// appearance; `nil` draws an empty track / no line.
    static func icon(
        fiveHour: Double?, sevenDay: Double?,
        fiveHourElapsed: Double?, sevenDayElapsed: Double?
    ) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            drawLabel(in: rect)
            drawBar(percentage: fiveHour, elapsed: fiveHourElapsed, y: sessionY, in: rect)
            drawBar(percentage: sevenDay, elapsed: sevenDayElapsed, y: weeklyY, in: rect)
            drawTimeLine(percent: fiveHourElapsed, barY: sessionY, in: rect)
            drawTimeLine(percent: sevenDayElapsed, barY: weeklyY, in: rect)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Claude Code usage"
        return image
    }

    /// Pace coloring: green when spend is comfortably behind the elapsed time,
    /// yellow as it approaches the line, red once it passes (spending faster
    /// than the window elapses). Falls back to green when elapsed is unknown.
    static func color(spent: Double, elapsed: Double?) -> NSColor {
        guard let elapsed else { return .systemGreen }
        let d = spent - elapsed
        if d < -paceWarnMargin { return .systemGreen }
        if d < 0 { return .systemYellow }
        return .systemRed
    }

    private static func drawLabel(in rect: NSRect) {
        // Sized and kerned to sit just inside the bar width (~22pt vs 24pt track).
        let label = NSAttributedString(string: "Claude", attributes: [
            .font: NSFont.systemFont(ofSize: 6.5, weight: .semibold),
            .kern: -0.3,
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.85),
        ])
        let textSize = label.size()
        label.draw(at: NSPoint(x: rect.midX - textSize.width / 2, y: rect.maxY - textSize.height))
    }

    private static func drawBar(percentage: Double?, elapsed: Double?, y: CGFloat, in rect: NSRect) {
        let track = NSRect(x: rect.minX + 2, y: y, width: rect.width - 4, height: barHeight)
        NSColor.labelColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

        guard let percentage else { return }
        let clamped = min(max(percentage, 0), 100)
        guard clamped > 0 else { return }
        // Proportional width with just a 1px floor, so the fill stays honest
        // against the time line instead of inflating small values to a nub.
        let width = max(track.width * clamped / 100, 1)
        let fill = NSRect(x: track.minX, y: track.minY, width: width, height: barHeight)
        color(spent: clamped, elapsed: elapsed).setFill()
        NSBezierPath(roundedRect: fill, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    }

    /// Thin neutral vertical line at the elapsed-time position, crossing the bar
    /// and extending 1px above and below it.
    private static func drawTimeLine(percent: Double?, barY: CGFloat, in rect: NSRect) {
        guard let percent else { return }
        let fraction = min(max(percent, 0), 100) / 100
        let x = (rect.minX + 2) + (rect.width - 4) * fraction
        let line = NSRect(x: x - 0.5, y: barY - 1, width: 1, height: barHeight + 2)
        NSColor.labelColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(rect: line).fill()
    }
}
