import AppKit

// A picture of the DMG window as Finder shows it in dark mode, for the README: the real background, Beanie's
// icon and the Applications folder at the spots tools/dmg_settings.py gives them.
// Usage: swift tools/make_dmg_preview.swift <background.png> <Beanie.app> <out.png>
let args = CommandLine.arguments
let background = NSImage(contentsOfFile: args[1])!
// Straight from the bundle's icns: Launch Services may not know a freshly built app yet.
let appIcon = NSImage(contentsOfFile: args[2] + "/Contents/Resources/Beanie.icns") ?? NSWorkspace.shared.icon(forFile: args[2])
let version = Bundle(path: args[2])?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")

let scale: CGFloat = 2, margin: CGFloat = 40, titleBar: CGFloat = 28
let content = NSSize(width: 640, height: 400)
let windowRect = NSRect(x: margin, y: margin, width: content.width, height: content.height + titleBar)
let canvas = NSSize(width: windowRect.width + margin * 2, height: windowRect.height + margin * 2)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width * scale), pixelsHigh: Int(canvas.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = canvas
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let frame = NSBezierPath(roundedRect: windowRect, xRadius: 12, yRadius: 12)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -8)
shadow.set()
NSColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1).setFill()
frame.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
frame.addClip()
// Title bar: traffic lights and the volume name.
NSColor(srgbRed: 0.17, green: 0.17, blue: 0.19, alpha: 1).setFill()
NSRect(x: windowRect.minX, y: windowRect.maxY - titleBar, width: windowRect.width, height: titleBar).fill()
for (i, color) in [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1), NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                   NSColor(srgbRed: 0.16, green: 0.79, blue: 0.25, alpha: 1)].enumerated() {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: windowRect.minX + 12 + CGFloat(i) * 20, y: windowRect.maxY - titleBar / 2 - 6, width: 12, height: 12)).fill()
}
let titleStyle = NSMutableParagraphStyle()
titleStyle.alignment = .center
NSAttributedString(string: "Beanotch \(version)", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                      .foregroundColor: NSColor(white: 0.85, alpha: 1), .paragraphStyle: titleStyle])
    .draw(in: NSRect(x: windowRect.minX, y: windowRect.maxY - titleBar + 6, width: windowRect.width, height: 18))

let contentRect = NSRect(x: windowRect.minX, y: windowRect.minY, width: content.width, height: content.height)
background.draw(in: contentRect)

// Icons centered at (170, 200) and (470, 200) from the content's top-left, labels under them.
func place(_ image: NSImage, _ name: String, x: CGFloat) {
    let size: CGFloat = 112
    let center = NSPoint(x: contentRect.minX + x, y: contentRect.maxY - 200)
    image.draw(in: NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white, .paragraphStyle: style])
        .draw(in: NSRect(x: center.x - 80, y: center.y - size / 2 - 22, width: 160, height: 18))
}
place(appIcon, "Beanie", x: 170)
place(folderIcon, "Applications", x: 470)
NSGraphicsContext.restoreGraphicsState()

NSColor(white: 1, alpha: 0.12).setStroke()
frame.lineWidth = 1
frame.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
