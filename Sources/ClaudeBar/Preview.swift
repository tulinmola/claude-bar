import AppKit

/// Development helper (`claude-bar --preview out.png`): renders the icon at
/// several usage levels, scaled up, against light and dark menu bar colors.
func renderPreview(to path: String) {
    // Session (5h), Weekly (7d), then the per-model sublimit — each as
    // (spend, elapsed). Ordered to double as the README legend. color = pace:
    // green cushion, yellow approaching the line, red past it; length = spend;
    // line = elapsed.
    func bar(_ spent: Double?, _ elapsed: Double?) -> IconRenderer.Bar {
        IconRenderer.Bar(percentage: spent, elapsed: elapsed)
    }
    let samples: [[IconRenderer.Bar]] = [
        [bar(10, 55), bar(18, 60), bar(24, 60)],        // comfortable — all under pace
        [bar(50, 55), bar(48, 55), bar(52, 55)],        // approaching the line
        [bar(78, 55), bar(82, 60), bar(88, 60)],        // over pace — spending too fast
        [bar(22, 60), bar(40, 72), bar(85, 72)],        // mixed — the sublimit binds first
        [bar(90, 99), bar(93, 99), bar(95, 99)],        // nearly full but still on pace
        [bar(30, 60), bar(45, 70)],                     // no sublimit — two bars re-center
        [bar(nil, nil), bar(nil, nil), bar(nil, nil)],  // no data yet
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
        let icon = IconRenderer.icon(bars: sample)
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
