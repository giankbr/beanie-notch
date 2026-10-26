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
        model = AppModel()
        controller = NotchController(model: model)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notchy")
        let menu = NSMenu()
        let open = NSMenuItem(title: "Open Notchy", action: #selector(openNotch), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        let clean = NSMenuItem(title: "Full System Clean", action: #selector(fullClean), keyEquivalent: "")
        clean.target = self
        menu.addItem(clean)
        let color = NSMenuItem(title: "Pick Color", action: #selector(pickColor), keyEquivalent: "")
        color.target = self
        menu.addItem(color)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Notchy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func openNotch() { controller.expand(pinned: true) }
    @objc private func fullClean() { model.cleaner.clean(.all) }
    @objc private func pickColor() { model.pickColor() }
}
