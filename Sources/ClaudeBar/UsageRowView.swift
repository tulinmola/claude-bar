import AppKit

/// One usage row in the menu: title and percentage on the top line, a wide
/// meter under it, then the elapsed reading and the exact reset time.
///
/// Same visual language as the menu bar icon — bar length is what you've spent,
/// the thin vertical line is how far into the window you are, and the color is
/// the pace between them — but with room to actually read it. The color comes
/// from `IconRenderer.color(spent:elapsed:)`, so the two surfaces can't drift
/// apart; only the geometry differs.
final class UsageRowView: NSView {
    /// These rows are the menu's widest item, so this effectively sets the
    /// panel width — generous enough that the meters read as charts rather
    /// than slivers, and that a full "42% elapsed · resets sáb, 19:59" never
    /// clips. AppKit adds a little trailing padding of its own, so the right
    /// margin sits marginally wider than the left; that's menu chrome, not
    /// something `inset` controls.
    private static let width: CGFloat = 285
    /// Matches where AppKit indents the text of a normal menu item, so these
    /// rows line up with "Refresh Now" below them.
    private static let inset: CGFloat = 21
    private static let trackHeight: CGFloat = 7

    private static let titleFont = NSFont.systemFont(ofSize: 13)
    private static let valueFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let detailFont = NSFont.systemFont(ofSize: 11)

    private let title: NSAttributedString
    private let value: NSAttributedString
    private let detail: NSAttributedString
    private let percentage: Double
    private let elapsed: Double?

    init(title: String, percentage: Double, elapsed: Double?, detail: String) {
        self.percentage = min(max(percentage, 0), 100)
        self.elapsed = elapsed
        self.title = NSAttributedString(string: title, attributes: [
            .font: Self.titleFont,
            .foregroundColor: NSColor.labelColor,
        ])
        self.value = NSAttributedString(string: String(format: "%.0f%%", percentage), attributes: [
            .font: Self.valueFont,
            .foregroundColor: NSColor.labelColor,
        ])
        self.detail = NSAttributedString(string: detail, attributes: [
            .font: Self.detailFont,
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let height = 5 + Self.lineHeight(Self.titleFont) + 6
            + Self.trackHeight + 6 + Self.lineHeight(Self.detailFont) + 7
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: height))
        // Custom-view menu items are invisible to VoiceOver otherwise.
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("\(title), \(self.value.string), \(detail)")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Top-down layout reads more naturally for a stack of rows than AppKit's
    /// bottom-left origin.
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        var y: CGFloat = 5
        title.draw(at: NSPoint(x: Self.inset, y: y))
        // Percentage right-aligned against the far edge of the meter below it.
        value.draw(at: NSPoint(x: bounds.maxX - Self.inset - value.size().width, y: y))
        y += Self.lineHeight(Self.titleFont) + 6

        drawMeter(in: NSRect(
            x: Self.inset, y: y,
            width: bounds.width - Self.inset * 2, height: Self.trackHeight))
        y += Self.trackHeight + 6

        detail.draw(at: NSPoint(x: Self.inset, y: y))
    }

    private func drawMeter(in track: NSRect) {
        let radius = track.height / 2
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius).fill()

        if percentage > 0 {
            // Floor at one track height so a low reading still reads as a dot
            // rather than a sliver.
            let width = max(track.width * percentage / 100, track.height)
            let fill = NSRect(x: track.minX, y: track.minY, width: width, height: track.height)
            IconRenderer.color(spent: percentage, elapsed: elapsed).setFill()
            NSBezierPath(roundedRect: fill, xRadius: radius, yRadius: radius).fill()
        }

        // The elapsed-time marker, overhanging the track so it stays legible
        // where the fill has already passed it.
        guard let elapsed else { return }
        let fraction = min(max(elapsed, 0), 100) / 100
        let x = track.minX + track.width * fraction
        let line = NSRect(x: x - 0.75, y: track.minY - 2.5, width: 1.5, height: track.height + 5)
        NSColor.labelColor.withAlphaComponent(0.55).setFill()
        NSBezierPath(rect: line).fill()
    }

    private static func lineHeight(_ font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }
}
