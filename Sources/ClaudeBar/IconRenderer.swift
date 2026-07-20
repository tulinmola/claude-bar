import AppKit

enum IconRenderer {
    static let size = NSSize(width: 28, height: 18)
    private static let barHeight: CGFloat = 3.5
    private static let barGap: CGFloat = 1.5

    /// How many points of cushion before the time line at which the bar turns
    /// from green (comfortable) to yellow (approaching the line).
    private static let paceWarnMargin: Double = 10

    /// One meter: how much you've spent, against how far into the window you
    /// are. A `nil` percentage draws an empty track; a `nil` elapsed draws no
    /// time line.
    struct Bar {
        var percentage: Double?
        var elapsed: Double?
    }

    /// Battery-style horizontal bars, top to bottom in the order given —
    /// Session (5h), Weekly (7d), and the per-model weekly sublimit when the
    /// account has one. Bar length is how much you've spent; a thin vertical
    /// line marks how far into the window we are; and the color is the pace
    /// between them — green with a comfortable cushion, yellow nearing the
    /// line, red once the fill passes it. The stack is centered, so an account
    /// without a sublimit gets two centered bars rather than a dead track.
    /// Colors adapt to the menu bar appearance.
    static func icon(bars: [Bar]) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            let ys = bars.indices.map { barY(index: $0, count: bars.count, in: rect) }
            // All bars, then all lines: a time line overhangs its bar by 1pt,
            // so drawing per-bar would let the next fill paint over it.
            for (bar, y) in zip(bars, ys) {
                drawBar(percentage: bar.percentage, elapsed: bar.elapsed, y: y, in: rect)
            }
            for (bar, y) in zip(bars, ys) {
                drawTimeLine(percent: bar.elapsed, barY: y, in: rect)
            }
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

    /// Vertically centers the whole stack; index 0 is the topmost bar.
    private static func barY(index: Int, count: Int, in rect: NSRect) -> CGFloat {
        let stack = CGFloat(count) * barHeight + CGFloat(max(count - 1, 0)) * barGap
        let top = rect.midY + stack / 2
        return top - CGFloat(index + 1) * barHeight - CGFloat(index) * barGap
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
