import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        // One notch at a time: opened again while it runs (from Launchpad, at login, after an update), it leaves the
        // running copy be.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            return
        }
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
    private var settingsWindow: SettingsWindow!

    // Settings saved under the app's earlier bundle ids come along once, the newest first.
    private static func carryOverSettings() {
        let defaults = UserDefaults.standard
        guard let id = Bundle.main.bundleIdentifier, defaults.persistentDomain(forName: id)?.isEmpty ?? true,
              let old = ["id.morfotech.beanie", "id.morfotech.brow"].lazy
                  .compactMap({ defaults.persistentDomain(forName: $0) }).first(where: { !$0.isEmpty }) else { return }
        defaults.setPersistentDomain(old, forName: id)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Font.registerAppFonts()
        Self.carryOverSettings()
        model = AppModel()
        controller = NotchController(model: model)
        settingsWindow = SettingsWindow(model: model)
        model.openSettings = { [weak self] section in self?.settingsWindow.show(section) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Beanotch")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Beanotch", action: #selector(openNotch), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let tools = NSMenuItem(title: "Tools…", action: #selector(openTools), keyEquivalent: "")
        tools.target = self
        menu.addItem(tools)
        menu.addItem(.separator())
        let clean = NSMenuItem(title: "Full System Clean", action: #selector(fullClean), keyEquivalent: "")
        clean.target = self
        menu.addItem(clean)
        let color = NSMenuItem(title: "Pick Color", action: #selector(pickColor), keyEquivalent: "")
        color.target = self
        menu.addItem(color)
        let measure = NSMenuItem(title: "Measure", action: #selector(measure), keyEquivalent: "")
        measure.target = self
        menu.addItem(measure)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Beanotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openNotch() { controller.expand(pinned: true) }
    @objc private func openSettings() { settingsWindow.show() }
    @objc private func openTools() { settingsWindow.show(.tools) }
    @objc private func measure() { model.measure() }
    @objc private func fullClean() { model.cleaner.clean(.all) }
    @objc private func pickColor() { model.pickColor() }
}
