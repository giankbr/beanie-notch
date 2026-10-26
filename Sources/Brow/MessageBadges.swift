import AppKit
import ApplicationServices

// Unread counts from the red badges on Dock icons, read through Accessibility. Only the number is seen, never
// the messages. Chat apps by default; any app with a badge when asked.
@MainActor
final class MessageBadges: ObservableObject {
    struct Badge: Identifiable, Equatable {
        let id: String
        let name: String
        let label: String
        let app: URL?
        // "•" and other non-numbers count as one.
        var count: Int { Int(label.filter(\.isNumber)) ?? 1 }
    }

    @Published private(set) var badges: [Badge] = []
    @Published private(set) var trusted = AXIsProcessTrusted()
    var allApps = false
    var onNew: ((Badge) -> Void)?
    private var timer: Timer?
    private var previous: [String: Int] = [:]
    private var primed = false
    private var bundleIDs: [URL: String] = [:]

    static let chatApps: Set<String> = [
        "net.whatsapp.WhatsApp", "desktop.WhatsApp", "ru.keepcoder.Telegram", "org.telegram.desktop", "com.tdesktop.Telegram",
        "com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.apple.MobileSMS", "com.apple.mail", "com.microsoft.teams2",
        "com.microsoft.teams", "org.whispersystems.signal-desktop", "jp.naver.line.mac", "com.facebook.archon",
        "com.microsoft.Outlook", "com.readdle.smartemail-Mac", "com.google.Chrome.app.gmail",
    ]

    var total: Int { badges.reduce(0) { $0 + $1.count } }

    func setEnabled(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else {
            badges = []
            primed = false
            return
        }
        poll()
        let t = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 0.5
        timer = t
    }

    // macOS shows its own prompt that leads to Privacy & Security › Accessibility.
    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        trusted = AXIsProcessTrustedWithOptions(options)
    }

    func open(_ badge: Badge) {
        if let app = badge.app { NSWorkspace.shared.open(app) }
    }

    private func poll() {
        trusted = AXIsProcessTrusted()
        guard trusted, let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return }
        let found = readDock(AXUIElementCreateApplication(dock.processIdentifier))
        // A badge that's new or has gone up is announced; the first read only learns what's already there.
        if primed {
            for badge in found where badge.count > (previous[badge.id] ?? 0) { onNew?(badge) }
        }
        primed = true
        previous = Dictionary(found.map { ($0.id, $0.count) }, uniquingKeysWith: max)
        if found != badges { badges = found }
    }

    private func readDock(_ dock: AXUIElement) -> [Badge] {
        var result: [Badge] = []
        for list in children(dock) {
            for item in children(list) {
                guard let label = value(item, "AXStatusLabel") as? String, !label.isEmpty else { continue }
                let url = value(item, kAXURLAttribute) as? URL
                let name = value(item, kAXTitleAttribute) as? String ?? url?.deletingPathExtension().lastPathComponent ?? "App"
                let id = url.map(bundleID) ?? name
                guard allApps || Self.chatApps.contains(id) else { continue }
                result.append(Badge(id: id, name: name, label: label, app: url))
            }
        }
        return result
    }

    private func bundleID(_ url: URL) -> String {
        if let known = bundleIDs[url] { return known }
        let id = Bundle(url: url)?.bundleIdentifier ?? url.lastPathComponent
        bundleIDs[url] = id
        return id
    }

    private func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var result: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &result) == .success ? result : nil
    }
}
