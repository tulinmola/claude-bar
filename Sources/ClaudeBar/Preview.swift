import AppKit

/// Development helper (`claude-bar --preview out.png`): renders the icon at
/// several usage levels, scaled up, against light and dark menu bar colors.
func renderPreview(to path: String) {
    // (fiveHour, sevenDay, fiveHourElapsed, sevenDayElapsed)
    // Ordered to double as the README legend. color = pace: green cushion,
    // yellow approaching the line, red past it; length = spend; line = elapsed.
    let samples: [(Double?, Double?, Double?, Double?)] = [
        (10, 18, 55, 60),    // comfortable — well under pace (green / green)
        (50, 48, 55, 55),    // approaching the line (yellow / yellow)
        (78, 82, 55, 60),    // over pace — spending too fast (red / red)
        (22, 85, 60, 72),    // mixed — session fine, weekly over (green / red)
        (90, 93, 99, 99),    // nearly full but still on pace (yellow / yellow)
        (nil, nil, nil, nil),// no data yet
    ]
    let scale: CGFloat = 6
    let cell = NSSize(width: IconRenderer.size.width * scale, height: IconRenderer.size.height * scale)
    let pad: CGFloat = 12
    let columnWidth = cell.width + pad * 2
    let canvas = NSSize(
        width: columnWidth * 2,
        height: (cell.height + pad) * CGFloat(samples.count) + pad)

    let image = NSImage(size: canvas)
    image.lockFocus()
    NSColor(white: 0.93, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: columnWidth, height: canvas.height).fill()
    NSColor(white: 0.13, alpha: 1).setFill()
    NSRect(x: columnWidth, y: 0, width: columnWidth, height: canvas.height).fill()

    for (index, sample) in samples.enumerated() {
        let icon = IconRenderer.icon(
            fiveHour: sample.0, sevenDay: sample.1,
            fiveHourElapsed: sample.2, sevenDayElapsed: sample.3)
        let y = canvas.height - pad - cell.height - CGFloat(index) * (cell.height + pad)
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            icon.draw(in: NSRect(x: pad, y: y, width: cell.width, height: cell.height))
        }
        NSAppearance(named: .darkAqua)?.performAsCurrentDrawingAppearance {
            icon.draw(in: NSRect(x: columnWidth + pad, y: y, width: cell.width, height: cell.height))
        }
    }
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:])
    else {
        fputs("preview: failed to encode PNG\n", stderr)
        return
    }
    try? png.write(to: URL(fileURLWithPath: path))
    print("preview written to \(path)")
}
