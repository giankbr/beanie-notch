import AppKit
import Foundation

struct CleanRecord: Codable, Identifiable {
    var id: Date { date }
    let date: Date
    let bytes: Int64
}

@MainActor
final class Cleaner: ObservableObject {
    enum Kind: Sendable { case temp, browser, all }

    @Published var tempBytes: Int64 = 0
    @Published var browserBytes: Int64 = 0
    @Published var browsers: [String] = []
    @Published var cleaning: Kind?
    @Published var progress: Double = 0
    @Published var history: [CleanRecord] = []

    var total: Int64 { tempBytes + browserBytes }

    private var scanning = false
    private var lastScan = Date.distantPast

    init() {
        if let data = UserDefaults.standard.data(forKey: "cleanHistory"),
           let saved = try? JSONDecoder().decode([CleanRecord].self, from: data) {
            history = saved
        }
        Task { await scan() }
    }

    func refreshIfStale() {
        guard cleaning == nil, Date().timeIntervalSince(lastScan) > 120 else { return }
        Task { await scan() }
    }

    func scan() async {
        guard !scanning else { return }
        scanning = true
        defer { scanning = false; lastScan = Date() }
        let skip = Self.runningBundleIDs()
        let result = await Task.detached(priority: .utility) { CleanScanner.scan(skip: skip) }.value
        tempBytes = result.temp
        browserBytes = result.browser
        browsers = result.browsers
    }

    func clean(_ kind: Kind) {
        guard cleaning == nil else { return }
        cleaning = kind
        progress = 0
        let skip = Self.runningBundleIDs()
        Task {
            let freed = await Task.detached(priority: .userInitiated) { [self] in
                let items = CleanScanner.items(kind, skip: skip)
                var freed: Int64 = 0
                for (i, item) in items.enumerated() {
                    freed += CleanScanner.remove(item)
                    let p = Double(i + 1) / Double(items.count)
                    await MainActor.run { self.progress = p }
                }
                return freed
            }.value
            history.append(CleanRecord(date: Date(), bytes: freed))
            if history.count > 30 { history.removeFirst(history.count - 30) }
            if let data = try? JSONEncoder().encode(history) {
                UserDefaults.standard.set(data, forKey: "cleanHistory")
            }
            await scan()
            cleaning = nil
        }
    }

    // Caches of apps that are open stay put: deleting them under a running app can break it.
    private static func runningBundleIDs() -> Set<String> {
        var ids = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        if let own = Bundle.main.bundleIdentifier { ids.insert(own) }
        return ids
    }
}

enum CleanScanner {
    struct Result: Sendable {
        let temp: Int64
        let browser: Int64
        let browsers: [String]
    }

    private static let fm = FileManager.default
    private static var library: URL { fm.homeDirectoryForCurrentUser.appendingPathComponent("Library") }
    private static var caches: URL { library.appendingPathComponent("Caches") }

    private static let browserDirs: [(name: String, paths: [String])] = [
        ("Chrome", ["Google/Chrome", "com.google.Chrome"]),
        ("Safari", ["com.apple.Safari"]),
        ("Edge", ["Microsoft Edge", "com.microsoft.edgemac"]),
        ("Brave", ["BraveSoftware", "com.brave.Browser"]),
        ("Firefox", ["Firefox", "org.mozilla.firefox"]),
        ("Arc", ["Arc", "company.thebrowser.Browser"]),
        ("Opera", ["com.operasoftware.Opera"]),
    ]

    private static var browserTopLevel: Set<String> {
        Set(browserDirs.flatMap { $0.paths.compactMap { $0.split(separator: "/").first.map(String.init) } })
    }

    private static func browserRoots() -> [(name: String, url: URL)] {
        browserDirs.flatMap { entry in entry.paths.map { (entry.name, caches.appendingPathComponent($0)) } }
            .filter { fm.fileExists(atPath: $0.1.path) }
    }

    static func scan(skip: Set<String>) -> Result {
        let roots = browserRoots()
        var seen: [String] = []
        for root in roots where !seen.contains(root.name) { seen.append(root.name) }
        return Result(
            temp: tempItems(skip: skip).reduce(0) { $0 + size($1) },
            browser: roots.reduce(0) { $0 + size($1.url) },
            browsers: seen
        )
    }

    static func items(_ kind: Cleaner.Kind, skip: Set<String>) -> [URL] {
        let browser = browserRoots().flatMap { children($0.url) }
        switch kind {
        case .temp: return tempItems(skip: skip)
        case .browser: return browser
        case .all: return tempItems(skip: skip) + browser
        }
    }

    private static func tempItems(skip: Set<String>) -> [URL] {
        let excluded = skip.union(browserTopLevel)
        let dayAgo = Date().addingTimeInterval(-86_400)
        let temp = children(URL(fileURLWithPath: NSTemporaryDirectory())).filter {
            ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()) < dayAgo
        }
        return children(caches).filter { !excluded.contains($0.lastPathComponent) }
            + children(library.appendingPathComponent("Logs"))
            + temp
    }

    private static func children(_ url: URL) -> [URL] {
        (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    }

    static func size(_ url: URL) -> Int64 {
        let key: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isDirectoryKey]
        guard let values = try? url.resourceValues(forKeys: key) else { return 0 }
        if values.isDirectory != true { return Int64(values.totalFileAllocatedSize ?? 0) }
        guard let e = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                                    errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in e {
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    static func remove(_ url: URL) -> Int64 {
        let before = size(url)
        try? fm.removeItem(at: url)
        return max(0, before - size(url))
    }
}
