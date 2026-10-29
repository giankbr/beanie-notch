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
        window.contentMinSize = NSSize(width: 560, height: 360)
        window.setContentSize(NSSize(width: 640, height: 430))
        window.center()
        window.setFrameAutosaveName("BeanotchSettingsWindow")
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
            // Just clear of the window's buttons at the top left; the title bar's own strip isn't kept.
            .padding(EdgeInsets(top: 30, leading: 10, bottom: 10, trailing: 12))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .ignoresSafeArea()
            .id(settings.styleKey)
    }
}
