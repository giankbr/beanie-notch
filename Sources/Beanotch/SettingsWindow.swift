import AppKit
import Combine
import SwiftUI

// Settings and Tools in a window of their own, so the notch keeps to what you glance at. One window, built on first
// use and kept after it closes.
@MainActor
final class SettingsWindow {
    private let model: AppModel
    private var window: NSWindow?
    private var sinks: Set<AnyCancellable> = []

    init(model: AppModel) { self.model = model }

    func show(_ section: SettingsView.Section? = nil) {
        if let section { model.settingsSection = section }
        if model.expanded { model.expanded = false }
        let window = window ?? build()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func build() -> NSWindow {
        let host = NSHostingController(rootView: SettingsWindowView().notchEnvironment(model))
        let window = NSWindow(contentViewController: host)
        window.title = "Beanotch"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 620, height: 400)
        window.setContentSize(NSSize(width: 760, height: 520))
        window.center()
        window.setFrameAutosaveName("BeanotchSettings")
        model.settings.$theme.sink { [weak window] theme in window?.appearance = theme.appearance }.store(in: &sinks)
        self.window = window
        return window
    }
}

private struct SettingsWindowView: View {
    @EnvironmentObject var settings: Settings

    var body: some View {
        SettingsView()
            .font(.app(size: 11))
            .foregroundStyle(Theme.ink)
            .symbolRenderingMode(.monochrome)
            // Clear of the window's buttons at the top left.
            .padding(EdgeInsets(top: 34, leading: 14, bottom: 14, trailing: 16))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .id(settings.styleKey)
    }
}
