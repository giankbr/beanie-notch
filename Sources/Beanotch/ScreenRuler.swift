import AppKit

// A ruler over every screen: crosshairs and the pointer's position, and a box with its size while dragging. The size
// is copied when the drag ends, ready for another measure; Esc or a right click puts the ruler away.
@MainActor
final class ScreenRuler {
    static let shared = ScreenRuler()
    var onMeasure: ((String) -> Void)?
    private var windows: [NSWindow] = []
    private var monitor: Any?

    var isShowing: Bool { !windows.isEmpty }

    func show() {
        guard windows.isEmpty else { return }
        for screen in NSScreen.screens {
            let window = RulerWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.ignoresMouseEvents = false
            window.acceptsMouseMovedEvents = true
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = RulerView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.scale = screen.backingScaleFactor
            view.onDone = { [weak self] in self?.hide() }
            view.onMeasure = { [weak self] text in self?.onMeasure?(text) }
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.hide(); return nil }
            return event
        }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        NSCursor.pop()
    }
}

private final class RulerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class RulerView: NSView {
    var scale: CGFloat = 2
    var onDone: (() -> Void)?
    var onMeasure: ((String) -> Void)?
    private var pointer: NSPoint?
    private var start: NSPoint?
    private var tracking: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseMoved(with event: NSEvent) { pointer = convert(event.locationInWindow, from: nil); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { pointer = nil; needsDisplay = true }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); pointer = start; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { pointer = convert(event.locationInWindow, from: nil); needsDisplay = true }
    override func rightMouseDown(with event: NSEvent) { onDone?() }

    override func mouseUp(with event: NSEvent) {
        guard let start, let end = pointer else { return }
        let w = abs(end.x - start.x), h = abs(end.y - start.y)
        if w >= 2 || h >= 2 {
            let text = "\(Int(w.rounded())) × \(Int(h.rounded()))"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            onMeasure?(text + " pt")
        }
        self.start = nil
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Nearly clear, but not quite: a fully clear window lets clicks through to what's below.
        NSColor.black.withAlphaComponent(0.06).setFill()
        bounds.fill()
        guard let p = pointer else { return }
        let accent = NSColor(red: 1, green: 0.27, blue: 0.4, alpha: 1)
        accent.withAlphaComponent(0.7).setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = 1
        cross.move(to: NSPoint(x: 0, y: p.y.rounded() + 0.5)); cross.line(to: NSPoint(x: bounds.maxX, y: p.y.rounded() + 0.5))
        cross.move(to: NSPoint(x: p.x.rounded() + 0.5, y: 0)); cross.line(to: NSPoint(x: p.x.rounded() + 0.5, y: bounds.maxY))
        cross.stroke()

        var label = "\(Int(p.x)), \(Int(bounds.height - p.y))"
        if let s = start {
            let rect = NSRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
            accent.withAlphaComponent(0.15).setFill()
            rect.fill()
            accent.setStroke()
            let box = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
            box.lineWidth = 1
            box.stroke()
            label = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded())) pt · \(Int((rect.width * scale).rounded())) × \(Int((rect.height * scale).rounded())) px"
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white,
        ]
        let text = NSAttributedString(string: label, attributes: attributes)
        let size = text.size()
        var origin = NSPoint(x: p.x + 12, y: p.y - size.height - 14)
        if origin.x + size.width + 12 > bounds.maxX { origin.x = p.x - size.width - 20 }
        if origin.y < 4 { origin.y = p.y + 12 }
        let back = NSRect(x: origin.x - 6, y: origin.y - 3, width: size.width + 12, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: back, xRadius: 6, yRadius: 6).fill()
        text.draw(at: origin)

        if start == nil {
            let hint = NSAttributedString(string: "Drag to measure · Esc to close", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.7),
            ])
            hint.draw(at: NSPoint(x: origin.x, y: origin.y - 16))
        }
    }
}
