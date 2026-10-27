import AppKit

@MainActor
final class Shelf: ObservableObject {
    @Published var items: [URL] = []
    @Published var grid = true

    // Files that have gone are dropped off the main thread: checking ones in Downloads or Desktop can wait on
    // macOS's access prompt.
    init() {
        let saved = (UserDefaults.standard.stringArray(forKey: "shelf") ?? []).map { URL(fileURLWithPath: $0) }
        items = saved
        Task {
            let present = await Task.detached(priority: .utility) {
                saved.filter { FileManager.default.fileExists(atPath: $0.path) }
            }.value
            if present.count != items.count { items = items.filter(present.contains) }
        }
    }

    func add(_ urls: [URL]) {
        for url in urls where !items.contains(url) { items.append(url) }
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    // The AirDrop sheet macOS shows from the Share menu, with these files already in it.
    func airDrop(_ urls: [URL]) {
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: urls) else { return }
        service.perform(withItems: urls)
    }

    func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.level = .statusBar + 1
        if panel.runModal() == .OK { add(panel.urls) }
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: "shelf")
    }
}
