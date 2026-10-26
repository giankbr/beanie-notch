import AppKit
import Carbon
import SwiftUI

// Tells when the app in front fills the notch's screen (a full-screen video, a presentation), so the notch can
// step aside. Window bounds come from the window list, which needs no permission.
@MainActor
final class FullScreenWatcher {
    var onChange: ((Bool) -> Void)?
    private(set) var isFullScreen = false

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                // The space switch animation settles a moment later.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    MainActor.assumeIsolated { self?.check() }
                }
            }
        }
    }

    func check() {
        let value = frontmostFillsScreen()
        guard value != isFullScreen else { return }
        isFullScreen = value
        onChange?(value)
    }

    private func frontmostFillsScreen() -> Bool {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return false }
        let size = screen.frame.size
        return windows.contains { window in
            guard window[kCGWindowOwnerPID as String] as? pid_t == pid,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return false }
            return rect.width >= size.width && rect.height >= size.height
        }
    }
}

// Caps Lock and keyboard-language changes, shown briefly in the notch.
@MainActor
final class KeyboardWatcher {
    var onNotice: ((Notice) -> Void)?
    var enabled = true
    private var capsOn = KeyboardWatcher.capsLock
    private var source = KeyboardWatcher.inputSource
    private var timer: Timer?

    init() {
        // Reading the modifier state needs no permission, unlike watching key events.
        let t = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCaps() }
        }
        t.tolerance = 0.1
        timer = t
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.inputChanged() }
        }
    }

    private func checkCaps() {
        let on = Self.capsLock
        guard on != capsOn else { return }
        capsOn = on
        guard enabled else { return }
        onNotice?(Notice(icon: on ? "capslock.fill" : "capslock", color: on ? Theme.amber : Theme.dim,
                         left: "Caps Lock", right: on ? "On" : "Off", duration: 1.6))
    }

    private func inputChanged() {
        let name = Self.inputSource
        guard name != source else { return }
        source = name
        guard enabled, !name.isEmpty else { return }
        onNotice?(Notice(icon: "keyboard", color: Theme.accent2, left: "Keyboard", right: name, duration: 2))
    }

    private static var capsLock: Bool {
        CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    }

    private static var inputSource: String {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let name = TISGetInputSourceProperty(current, kTISPropertyLocalizedName) else { return "" }
        return Unmanaged<CFString>.fromOpaque(name).takeUnretainedValue() as String
    }
}

// Water, eye-break and stretch reminders, only while someone is at the Mac and between 8:00 and 22:00.
@MainActor
final class HealthReminders {
    var onNotice: ((Notice) -> Void)?
    var waterEvery = 0 { didSet { lastWater = Date() } }
    var eyeBreaks = false { didSet { lastEyes = Date() } }
    var stretchEvery = 0 { didSet { lastStretch = Date() } }
    private var lastWater = Date(), lastEyes = Date(), lastStretch = Date()
    private var timer: Timer?

    init() {
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 10
        timer = t
    }

    private func tick() {
        guard waterEvery > 0 || eyeBreaks || stretchEvery > 0 else { return }
        let now = Date()
        guard (8..<22).contains(Calendar.current.component(.hour, from: now)) else { return }
        // Away from the Mac: the clocks start over when they're back.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        if idle > 300 {
            lastWater = now
            lastEyes = now
            lastStretch = now
            return
        }
        if eyeBreaks, now.timeIntervalSince(lastEyes) >= 20 * 60 {
            lastEyes = now
            onNotice?(Notice(icon: "eye", color: Theme.accent2, left: "Eye break", right: "Look far away for 20 s", duration: 8, essential: true))
        } else if waterEvery > 0, now.timeIntervalSince(lastWater) >= Double(waterEvery * 60) {
            lastWater = now
            onNotice?(Notice(icon: "drop.fill", color: Theme.accent, left: "Drink water", right: "A glass now", duration: 8, essential: true))
        } else if stretchEvery > 0, now.timeIntervalSince(lastStretch) >= Double(stretchEvery * 60) {
            lastStretch = now
            onNotice?(Notice(icon: "figure.walk", color: Theme.amber, left: "Stand up", right: "Stretch for a minute", duration: 8, essential: true))
        }
    }
}

extension PrayerTimes.Place {
    // Great-circle bearing to the Kaaba, in degrees clockwise from true north.
    var qibla: Double {
        let rad = Double.pi / 180
        let kaabaLat = 21.4225 * rad, kaabaLng = 39.8262 * rad
        let lat = self.lat * rad, dLng = kaabaLng - lng * rad
        let bearing = atan2(sin(dLng), cos(lat) * tan(kaabaLat) - sin(lat) * cos(dLng)) / rad
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }

    var qiblaDirection: String {
        ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Int((qibla + 22.5) / 45) % 8]
    }
}
