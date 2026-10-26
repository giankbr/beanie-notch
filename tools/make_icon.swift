import AppKit

// Graphite tile with a mint panel dropping out of a notch.
let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let tileShape = NSBezierPath(roundedRect: tile, xRadius: 185, yRadius: 185)
NSGradient(colors: [NSColor(srgbRed: 0.05, green: 0.06, blue: 0.08, alpha: 1),
                    NSColor(srgbRed: 0.17, green: 0.19, blue: 0.24, alpha: 1)])!.draw(in: tileShape, angle: 90)

// The panel: a neck at the top edge that widens into a rounded body.
let mint = NSColor(srgbRed: 0.33, green: 0.9, blue: 0.74, alpha: 1)
let top: CGFloat = 924, neckW: CGFloat = 250, neckH: CGFloat = 70
let bodyW: CGFloat = 560, bodyBottom: CGFloat = 430, r: CGFloat = 90, f: CGFloat = 34
let cx: CGFloat = 512
let p = NSBezierPath()
p.move(to: NSPoint(x: cx - neckW / 2, y: top))
p.line(to: NSPoint(x: cx + neckW / 2, y: top))
p.line(to: NSPoint(x: cx + neckW / 2, y: top - neckH + f))
p.curve(to: NSPoint(x: cx + neckW / 2 + f, y: top - neckH), controlPoint1: NSPoint(x: cx + neckW / 2, y: top - neckH),
        controlPoint2: NSPoint(x: cx + neckW / 2, y: top - neckH))
p.line(to: NSPoint(x: cx + bodyW / 2 - 40, y: top - neckH))
p.curve(to: NSPoint(x: cx + bodyW / 2, y: top - neckH - 40), controlPoint1: NSPoint(x: cx + bodyW / 2, y: top - neckH),
        controlPoint2: NSPoint(x: cx + bodyW / 2, y: top - neckH))
p.line(to: NSPoint(x: cx + bodyW / 2, y: bodyBottom + r))
p.curve(to: NSPoint(x: cx + bodyW / 2 - r, y: bodyBottom), controlPoint1: NSPoint(x: cx + bodyW / 2, y: bodyBottom),
        controlPoint2: NSPoint(x: cx + bodyW / 2, y: bodyBottom))
p.line(to: NSPoint(x: cx - bodyW / 2 + r, y: bodyBottom))
p.curve(to: NSPoint(x: cx - bodyW / 2, y: bodyBottom + r), controlPoint1: NSPoint(x: cx - bodyW / 2, y: bodyBottom),
        controlPoint2: NSPoint(x: cx - bodyW / 2, y: bodyBottom))
p.line(to: NSPoint(x: cx - bodyW / 2, y: top - neckH - 40))
p.curve(to: NSPoint(x: cx - bodyW / 2 + 40, y: top - neckH), controlPoint1: NSPoint(x: cx - bodyW / 2, y: top - neckH),
        controlPoint2: NSPoint(x: cx - bodyW / 2, y: top - neckH))
p.line(to: NSPoint(x: cx - neckW / 2 - f, y: top - neckH))
p.curve(to: NSPoint(x: cx - neckW / 2, y: top - neckH + f), controlPoint1: NSPoint(x: cx - neckW / 2, y: top - neckH),
        controlPoint2: NSPoint(x: cx - neckW / 2, y: top - neckH))
p.close()

NSGraphicsContext.saveGraphicsState()
tileShape.addClip()
mint.setFill()
p.fill()
NSGraphicsContext.restoreGraphicsState()

// Three bars inside the panel, like the live meters.
let graphite = NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 0.9)
graphite.setFill()
for (i, w) in [300.0, 220.0, 360.0].enumerated() {
    let y = 730 - CGFloat(i) * 80
    NSBezierPath(roundedRect: NSRect(x: cx - 200, y: y, width: CGFloat(w), height: 36), xRadius: 18, yRadius: 18).fill()
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
