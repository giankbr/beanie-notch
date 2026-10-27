import AppKit

// The DMG window's background, 640×400 points: graphite like the icon, a notch at the top, and a mint arrow
// from where Beanie sits (x 170) to Applications (x 470). Written at 1× and 2× next to the given path.
let size = NSSize(width: 640, height: 400)
let mint = NSColor(srgbRed: 0.33, green: 0.9, blue: 0.74, alpha: 1)

func render(scale: CGFloat, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGradient(colors: [NSColor(srgbRed: 0.055, green: 0.06, blue: 0.07, alpha: 1),
                        NSColor(srgbRed: 0.13, green: 0.145, blue: 0.17, alpha: 1)])!
        .draw(in: NSRect(origin: .zero, size: size), angle: 90)

    // A notch along the top edge, with a faint mint line under it like the open panel's glow.
    let notch = NSBezierPath(roundedRect: NSRect(x: size.width / 2 - 90, y: size.height - 24, width: 180, height: 40), xRadius: 14, yRadius: 14)
    NSColor.black.setFill()
    notch.fill()
    mint.withAlphaComponent(0.55).setFill()
    NSBezierPath(roundedRect: NSRect(x: size.width / 2 - 34, y: size.height - 30, width: 68, height: 2.5), xRadius: 1.25, yRadius: 1.25).fill()

    // The arrow, at the icons' height (y 200 from the top).
    let y = size.height - 200
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 262, y: y))
    shaft.line(to: NSPoint(x: 370, y: y))
    shaft.lineWidth = 3
    shaft.lineCapStyle = .round
    shaft.setLineDash([2, 9], count: 2, phase: 0)
    mint.setStroke()
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 366, y: y + 9))
    head.line(to: NSPoint(x: 378, y: y))
    head.line(to: NSPoint(x: 366, y: y - 9))
    head.lineWidth = 3
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.stroke()

    func text(_ string: String, size points: CGFloat, weight: NSFont.Weight, color: NSColor, y: CGFloat) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: points, weight: weight),
                                                         .foregroundColor: color, .paragraphStyle: style]
        NSAttributedString(string: string, attributes: attributes).draw(in: NSRect(x: 0, y: y, width: size.width, height: points * 1.5))
    }
    text("Drag Beanie into Applications", size: 15, weight: .semibold, color: NSColor(white: 0.92, alpha: 1), y: 76)
    text("Then open it from Applications. The first time, right-click it and choose Open.", size: 11, weight: .regular,
         color: NSColor(white: 0.6, alpha: 1), y: 54)

    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
render(scale: 1, to: out)
render(scale: 2, to: out.deletingLastPathComponent().appendingPathComponent(out.deletingPathExtension().lastPathComponent + "@2x.png"))
