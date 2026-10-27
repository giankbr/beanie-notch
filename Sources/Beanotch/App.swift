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

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Beanotch")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Beanotch", action: #selector(openNotch), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let clean = NSMenuItem(title: "Full System Clean", action: #selector(fullClean), keyEquivalent: "")
        clean.target = self
        menu.addItem(clean)
        let color = NSMenuItem(title: "Pick Color", action: #selector(pickColor), keyEquivalent: "")
        color.target = self
        menu.addItem(color)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Beanotch", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openNotch() { controller.expand(pinned: true) }
    @objc private func fullClean() { model.cleaner.clean(.all) }
    @objc private func pickColor() { model.pickColor() }
}
