import AppKit
import Combine
import SwiftUI

final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isFloatingPanel = true
        // After isFloatingPanel, which resets the level to .floating (below the menu bar). Above the menu bar
        // and its status items, so the Mini tabs that sit in that row take the clicks.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    // The panel sits over the menu bar; AppKit would otherwise push it below.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

// What the notch zone and the panel do as a file drag moves over them.
struct DropHandlers {
    var enter: () -> Void = {}
    var move: (CGFloat) -> Void = { _ in }
    var exit: () -> Void = {}
    var end: () -> Void = {}
    var drop: ([URL]) -> Void = { _ in }
}

private func droppedURLs(_ sender: NSDraggingInfo) -> [URL] {
    sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
}

// Sits exactly over the hardware notch, where nothing else can be clicked, and always takes the mouse: it
// opens the panel on hover and catches files dragged onto the notch while the panel is closed.
final class DropZoneView: NSView {
    var onHover: () -> Void = {}
    var onClick: () -> Void = {}
    var onScroll: (NSEvent) -> Void = { _ in }
    var drops = DropHandlers()

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover() }
    override func mouseDown(with event: NSEvent) { onClick() }
    override func scrollWheel(with event: NSEvent) { onScroll(event) }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        drops.enter()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        drops.move(convert(sender.draggingLocation, from: nil).x / max(bounds.width, 1))
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { drops.exit() }
    override func draggingEnded(_ sender: NSDraggingInfo) { drops.end() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(sender)
        drops.drop(urls)
        return !urls.isEmpty
    }
}

// The panel's hosting view, so files dropped anywhere on the open panel land on the Shelf.
final class NotchHostingView: NSHostingView<AnyView> {
    var drops = DropHandlers()
    // Scrolls over the notch strip at the top; returns false to let the panel's content scroll instead.
    var onScroll: (NSEvent) -> Bool = { _ in false }

    override func scrollWheel(with event: NSEvent) {
        if !onScroll(event) { super.scrollWheel(with: event) }
    }

    required init(rootView: AnyView) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        drops.enter()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        drops.move(convert(sender.draggingLocation, from: nil).x / max(bounds.width, 1))
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { drops.exit() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = droppedURLs(sender)
        drops.drop(urls)
        return !urls.isEmpty
    }
}

@MainActor
final class NotchController {
    private let model: AppModel
    private let panel = NotchPanel()
    private let dropZone = NotchPanel()
    private var monitors: [Any] = []
    private var sinks: Set<AnyCancellable> = []
    private var watchTimer: Timer?
    private var outsideSince: Date?
    private var screenFrame: NSRect = .zero
    private var hotKey: HotKey?
    private let fullScreen = FullScreenWatcher()

    init(model: AppModel) {
        self.model = model
        let host = NotchHostingView(rootView: AnyView(NotchRootView().notchEnvironment(model)))
        host.sizingOptions = []
        panel.contentView = host

        let zone = DropZoneView()
        zone.onHover = { [weak self] in
            guard let self, model.settings.openOnHover else { return }
            expand(pinned: false)
        }
        zone.onClick = { [weak self] in
            // A message notice opens its app; otherwise the panel opens.
            if let app = self?.model.notice?.open {
                NSWorkspace.shared.open(app)
            } else {
                self?.expand(pinned: true)
            }
        }
        zone.onScroll = { [weak self] e in self?.scrolled(e) }
        host.onScroll = { [weak self] e in
            guard let self, let window = e.window, e.locationInWindow.y > window.frame.height - model.closedHeight else { return false }
            scrolled(e)
            return true
        }
        let drops = DropHandlers(
            enter: { [weak self] in self?.dragEntered() },
            move: { [weak self] fraction in
                // The Shelf's left third hands what's dropped there to the AI, its right third sends it by AirDrop.
                guard let split = self?.model.dropSplit else { return }
                let airDrop = fraction > split.airDrop, ai = fraction < split.ai
                if self?.model.dropToAirDrop != airDrop { self?.model.dropToAirDrop = airDrop }
                if self?.model.dropToAI != ai { self?.model.dropToAI = ai }
            },
            exit: { [weak self] in self?.dragExited() },
            end: { [weak self] in self?.endDrag() },
            drop: { [weak self] urls in self?.dropped(urls) }
        )
        zone.drops = drops
        host.drops = drops
        dropZone.contentView = zone
        dropZone.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 4)
        dropZone.ignoresMouseEvents = false

        layout()
        panel.orderFrontRegardless()
        dropZone.orderFrontRegardless()

        model.$expanded.sink { [weak self] open in self?.expandedChanged(open) }.store(in: &sinks)
        model.openPanel = { [weak self] in
            self?.expand(pinned: true)
            self?.model.pinned = true
        }
        let settings = model.settings
        Publishers.CombineLatest3(settings.$hotkey, settings.$hotkeyCode, settings.$hotkeyModifiers)
            .sink { [weak self] on, code, modifiers in
                // The old one goes first: Carbon won't register the same combination twice.
                self?.hotKey = nil
                if on { self?.hotKey = HotKey(keyCode: code, modifiers: modifiers) { [weak self] in self?.toggle() } }
            }
            .store(in: &sinks)
        settings.$size.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &sinks)
        settings.$layout.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &sinks)
        settings.$notchStyle.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.layout() }
        }.store(in: &sinks)
        settings.$theme.sink { [weak self] theme in self?.panel.appearance = theme.appearance }.store(in: &sinks)
        fullScreen.onChange = { [weak self] _ in self?.applyFullScreen() }
        settings.$hideInFullScreen.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyFullScreen() }
        }.store(in: &sinks)

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in MainActor.assumeIsolated { self?.layout() } }

        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e, local: false) }
        }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown], handler: { [weak self] e in
            MainActor.assumeIsolated { self?.handle(e, local: true) }
            return e
        }) { monitors.append(m) }
    }

    private var swipeDistance: CGFloat = 0
    private var swiped = false

    // Over the notch: a sideways two-finger swipe changes the track, scrolling up and down sets the volume.
    private func scrolled(_ e: NSEvent) {
        guard model.settings.gestures, e.momentumPhase.isEmpty else { return }
        if e.phase == .began || e.phase.isEmpty && !e.hasPreciseScrollingDeltas { swipeDistance = 0; swiped = false }
        let inverted = e.isDirectionInvertedFromDevice
        let dx = e.scrollingDeltaX, dy = e.scrollingDeltaY
        if abs(dx) > abs(dy) {
            // Positive when the fingers move right, whatever the scroll direction setting.
            swipeDistance += inverted ? dx : -dx
            if !swiped, abs(swipeDistance) > 60, model.media.now != nil {
                swiped = true
                if swipeDistance > 0 { model.media.previous() } else { model.media.next() }
            }
        } else if dy != 0 {
            let up = inverted ? -dy : dy
            model.nudgeVolume(by: e.hasPreciseScrollingDeltas ? Float(up) * 0.004 : (up > 0 ? 1 : -1) / 16)
        }
    }

    // Out of the way while a full-screen app is in front, back as soon as it isn't.
    private func applyFullScreen() {
        if model.settings.hideInFullScreen, fullScreen.isFullScreen {
            collapse()
            panel.orderOut(nil)
            dropZone.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
            dropZone.orderFrontRegardless()
        }
    }

    private var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.screens.first
    }

    private func layout() {
        guard let screen else { return }
        screenFrame = screen.frame
        if screen.safeAreaInsets.top > 0 {
            let left = screen.auxiliaryTopLeftArea?.width ?? 0
            let right = screen.auxiliaryTopRightArea?.width ?? 0
            // Never taller than the menu bar, or the closed notch hangs over the top of app windows.
            let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
            let height = menuBar > 0 ? min(screen.safeAreaInsets.top, menuBar) : screen.safeAreaInsets.top
            model.closedSize = CGSize(width: screen.frame.width - left - right, height: height)
        } else {
            model.closedSize = CGSize(width: 190, height: max(24, screen.frame.maxY - screen.visibleFrame.maxY))
        }
        let size = CGSize(width: model.openSize.width + 60, height: model.openSize.height + 40)
        panel.setFrame(NSRect(x: screenFrame.midX - size.width / 2, y: screenFrame.maxY - size.height,
                              width: size.width, height: size.height), display: true)
        if !model.dropTargeted { dropZone.setFrame(notchFrame, display: true) }
    }

    private var notchFrame: NSRect {
        let notch = model.closedSize
        return NSRect(x: screenFrame.midX - notch.width / 2, y: screenFrame.maxY - notch.height,
                      width: notch.width, height: notch.height)
    }

    private var openFrame: NSRect {
        let open = model.openSize
        return NSRect(x: screenFrame.midX - open.width / 2, y: screenFrame.maxY - open.height, width: open.width, height: open.height)
    }

    // While a file is being dragged, the drop zone (which never ignores the mouse) spans the whole panel:
    // macOS doesn't pick up a window as a drop target mid-drag if it was ignoring the mouse when the drag began.
    private func dragEntered() {
        expand(pinned: false)
        model.tab = .shelf
        model.dropTargeted = true
        dropZone.setFrame(openFrame, display: false)
    }

    private func dragExited() {
        guard model.dropTargeted, !isInsideOpen(NSEvent.mouseLocation) || NSEvent.pressedMouseButtons == 0 else { return }
        endDrag()
    }

    private func dropped(_ urls: [URL]) {
        if model.dropToAI, let file = urls.first {
            model.aiFile = file
            model.tab = .ai
        } else if model.dropToAirDrop {
            model.shelf.airDrop(urls)
        } else {
            model.shelf.add(urls)
        }
        endDrag()
    }

    private func endDrag() {
        model.dropTargeted = false
        model.dropToAirDrop = false
        model.dropToAI = false
        dropZone.setFrame(notchFrame, display: false)
    }

    private var hotRect: NSRect {
        let w = model.closedWidth + 20, h = model.closedHeight + 6
        return NSRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h + 1)
    }

    // The open panel's own area: the notch-wide neck in the menu bar plus the body below it. The menu bar
    // items beside the notch stay outside, so reaching for them closes the panel.
    private func isInsideOpen(_ p: NSPoint) -> Bool {
        let s = model.openSize, h = model.closedSize.height
        let body = NSRect(x: screenFrame.midX - s.width / 2, y: screenFrame.maxY - s.height,
                          width: s.width, height: s.height - h).insetBy(dx: -8, dy: -8)
        // Mini's tabs fill the menu bar row, so the whole width of that row counts.
        let neckWidth = model.settings.size == .mini ? s.width : model.closedSize.width
        let neck = NSRect(x: screenFrame.midX - neckWidth / 2, y: screenFrame.maxY - h, width: neckWidth, height: h + 1)
        return body.contains(p) || neck.contains(p)
    }

    private func handle(_ e: NSEvent, local: Bool) {
        switch e.type {
        case .keyDown:
            if e.keyCode == 53, model.expanded { collapse() }
        case .leftMouseDown:
            if !local, model.expanded, !isInsideOpen(NSEvent.mouseLocation) { collapse() }
        default:
            if !model.expanded, model.settings.openOnHover, panel.isVisible, hotRect.contains(NSEvent.mouseLocation) {
                expand(pinned: false)
            }
        }
    }

    private func expandedChanged(_ open: Bool) {
        panel.ignoresMouseEvents = !open
        model.stats.setActive(open)
        model.media.setActive(open)
        watchTimer?.invalidate()
        watchTimer = nil
        guard open else { return }
        model.cleaner.refreshIfStale()
        outsideSince = nil
        let t = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.watchMouse() }
        }
        t.tolerance = 0.05
        watchTimer = t
    }

    // Closes only after the pointer has stayed away for a while, and never mid-drag.
    private func watchMouse() {
        // A drag that ended without a drop or an exit (cancelled over the panel) must not leave the drop zone
        // stretched over the panel, where it would swallow every click.
        if model.dropTargeted, NSEvent.pressedMouseButtons == 0 { endDrag() }
        if isInsideOpen(NSEvent.mouseLocation) {
            model.pinned = false
            outsideSince = nil
            return
        }
        // A Claude Code permission request keeps it open until it's answered.
        if model.pinned || NSEvent.pressedMouseButtons != 0 || !model.claude.pending.isEmpty {
            outsideSince = nil
            return
        }
        let since = outsideSince ?? Date()
        outsideSince = since
        if Date().timeIntervalSince(since) > model.settings.closeDelay { collapse() }
    }

    func toggle() {
        if model.expanded {
            collapse()
        } else {
            expand(pinned: true)
            panel.makeKey()
        }
    }

    func expand(pinned: Bool) {
        guard !model.expanded else { return }
        model.pinned = pinned
        panel.orderFrontRegardless()
        dropZone.orderFrontRegardless()
        model.expanded = true
    }

    func collapse() {
        model.pinned = false
        model.expanded = false
    }
}
