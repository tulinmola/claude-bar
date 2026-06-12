import AppKit

enum IconRenderer {
    static let size = NSSize(width: 28, height: 18)
    private static let barHeight: CGFloat = 3.5

    /// A tiny "Claude" label over two battery-style horizontal bars:
    /// Session (5h) on top, Weekly (7d) below. Label and empty tracks adapt
    /// to the menu bar appearance; `nil` draws an empty track.
    static func icon(fiveHour: Double?, sevenDay: Double?) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            drawLabel(in: rect)
            drawBar(percentage: fiveHour, y: 5, in: rect)
            drawBar(percentage: sevenDay, y: 0, in: rect)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = "Claude Code usage"
        return image
    }

    static func color(for percentage: Double) -> NSColor {
        if percentage >= 90 { return .systemRed }
        if percentage >= 70 { return .systemOrange }
        return .systemGreen
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

    private static func drawBar(percentage: Double?, y: CGFloat, in rect: NSRect) {
        let track = NSRect(x: rect.minX + 2, y: y, width: rect.width - 4, height: barHeight)
        NSColor.labelColor.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: track, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()

        guard let percentage else { return }
        let clamped = min(max(percentage, 0), 100)
        guard clamped > 0 else { return }
        let width = max(track.width * clamped / 100, barHeight)
        let fill = NSRect(x: track.minX, y: track.minY, width: width, height: barHeight)
        color(for: clamped).setFill()
        NSBezierPath(roundedRect: fill, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    }
}
