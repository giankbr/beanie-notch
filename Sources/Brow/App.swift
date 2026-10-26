import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var controller: NotchController!
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Font.registerAppFonts()
        Self.migrateFromNotchy()
        model = AppModel()
        controller = NotchController(model: model)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Brow")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Brow", action: #selector(openNotch), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let clean = NSMenuItem(title: "Full System Clean", action: #selector(fullClean), keyEquivalent: "")
        clean.target = self
        menu.addItem(clean)
        let color = NSMenuItem(title: "Pick Color", action: #selector(pickColor), keyEquivalent: "")
        color.target = self
        menu.addItem(color)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Brow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    // The app was called Notchy: its settings, pins and Shelf come along the first time Brow opens.
    private static func migrateFromNotchy() {
        let defaults = UserDefaults.standard
        guard let id = Bundle.main.bundleIdentifier, !defaults.bool(forKey: "migratedFromNotchy") else { return }
        if let old = defaults.persistentDomain(forName: "id.morfotech.notchy"), !old.isEmpty {
            defaults.setPersistentDomain(old.merging(defaults.persistentDomain(forName: id) ?? [:]) { $1 }, forName: id)
        }
        defaults.set(true, forKey: "migratedFromNotchy")
    }

    @objc private func openNotch() { controller.expand(pinned: true) }
    @objc private func fullClean() { model.cleaner.clean(.all) }
    @objc private func pickColor() { model.pickColor() }
}
