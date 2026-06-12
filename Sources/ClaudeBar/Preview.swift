import AppKit

/// Development helper (`claude-bar --preview out.png`): renders the icon at
/// several usage levels, scaled up, against light and dark menu bar colors.
func renderPreview(to path: String) {
    let samples: [(Double?, Double?)] = [
        (12, 34), (45, 67), (68, 72), (85, 78), (95, 88), (100, 96), (0, 41), (nil, nil),
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
        let icon = IconRenderer.icon(fiveHour: sample.0, sevenDay: sample.1)
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
