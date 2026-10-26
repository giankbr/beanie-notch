import AppKit

@MainActor
final class Uninstaller: ObservableObject {
    struct AppInfo: Identifiable, Hashable {
        let url: URL
        let name: String
        let bundleID: String
        let version: String
        var id: URL { url }
    }

    struct Leftover: Identifiable {
        let url: URL
        let size: Int64
        var id: URL { url }
        // Mac-wide files (outside the home folder) need an administrator to remove.
        var needsAdmin: Bool { !url.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) }
    }

    @Published private(set) var apps: [AppInfo] = []
    @Published private(set) var selected: AppInfo?
    @Published private(set) var appSize: Int64 = 0
    @Published private(set) var leftovers: [Leftover] = []
    @Published private(set) var loading = false
    @Published private(set) var confirming = false
    @Published var message: String?

    var total: Int64 { appSize + leftovers.reduce(0) { $0 + $1.size } }

    func loadApps(force: Bool = false) async {
        guard apps.isEmpty || force else { return }
        apps = await Task.detached(priority: .userInitiated) { Self.findApps() }.value
    }

    func select(_ app: AppInfo) {
        selected = app
        confirming = false
        message = nil
        loading = true
        Task {
            let (size, found) = await Task.detached(priority: .userInitiated) {
                (CleanScanner.size(app.url), Self.findLeftovers(app))
            }.value
            guard selected == app else { return }
            appSize = size
            leftovers = found
            loading = false
        }
    }

    func trash() {
        guard let app = selected else { return }
        if !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty {
            message = "Quit \(app.name) first"
            return
        }
        guard confirming else {
            confirming = true
            return
        }
        confirming = false
        let targets = [app.url] + leftovers.filter { !$0.needsAdmin }.map(\.url)
        let adminOnly = leftovers.filter(\.needsAdmin).count
        Task {
            let failed = await Task.detached(priority: .userInitiated) {
                targets.filter { (try? FileManager.default.trashItem(at: $0, resultingItemURL: nil)) == nil }
            }.value
            if failed.contains(app.url) {
                message = "Couldn't move \(app.name): allow Notchy in Privacy › App Management"
            } else {
                let skipped = failed.count + adminOnly
                message = skipped == 0 ? "\(app.name) moved to Trash"
                    : "\(app.name) moved to Trash · \(skipped) item(s) need an administrator, see Finder"
                apps.removeAll { $0 == app }
                selected = nil
                leftovers = []
            }
        }
    }

    nonisolated private static func findApps() -> [AppInfo] {
        let fm = FileManager.default
        let roots = ["/Applications", "/Applications/Utilities"].map { URL(fileURLWithPath: $0) }
            + [fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
        var found: [AppInfo] = []
        for root in roots {
            for url in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "app" {
                // Apple's own apps live on the sealed system volume and can't be removed.
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !id.hasPrefix("com.apple.") else { continue }
                found.append(AppInfo(url: url, name: url.deletingPathExtension().lastPathComponent, bundleID: id,
                                     version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
            }
        }
        return found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // Every place apps leave things behind, in the user's Library and the Mac-wide one (the list Pearcleaner
    // searches). An entry counts when its name holds the bundle id, or is the app's name (long enough not to
    // catch unrelated folders).
    nonisolated private static let userFolders = [
        "Application Support", "Application Scripts", "Caches", "Containers", "Group Containers", "HTTPStorages",
        "LaunchAgents", "Logs", "Preferences", "Preferences/ByHost", "Saved Application State", "WebKit",
        "Internet Plug-Ins", "PreferencePanes", "QuickLook", "Application Support/CrashReporter",
    ]
    nonisolated private static let systemFolders = [
        "/Library/Application Support", "/Library/Caches", "/Library/LaunchAgents", "/Library/LaunchDaemons",
        "/Library/Logs", "/Library/Preferences", "/Library/PrivilegedHelperTools", "/Library/Internet Plug-Ins",
        "/Library/PreferencePanes", "/Users/Shared/Library/Application Support",
    ]

    nonisolated private static func findLeftovers(_ app: AppInfo) -> [Leftover] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        let folders = userFolders.map { home.appendingPathComponent($0) } + systemFolders.map { URL(fileURLWithPath: $0) }
        let id = app.bundleID.lowercased()
        let name = app.name.lowercased().filter { !$0.isWhitespace }
        // Exact matches only: "com.google.chrome.for.testing" belongs to another app than "com.google.chrome".
        func matches(_ entry: String) -> Bool {
            let e = entry.lowercased()
            if e == id || e.hasSuffix("." + id) { return true }
            if e.hasPrefix(id + ".") {
                let next = e.dropFirst(id.count + 1).split(separator: ".").first.map(String.init) ?? ""
                let knownExtensions: Set = ["plist", "savedstate", "binarycookies", "log"]
                let hostID = next.count >= 8 && next.allSatisfy { $0.isHexDigit || $0 == "-" }
                return knownExtensions.contains(next) || hostID
            }
            guard name.count >= 4 else { return false }
            let stem = (e as NSString).deletingPathExtension.filter { !$0.isWhitespace }
            return stem == name
        }
        var seen = Set<String>()
        return folders.flatMap { folder in
            ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).filter(matches).map { folder.appendingPathComponent($0) }
        }
        .filter { seen.insert($0.path).inserted && $0.path != app.url.path }
        .map { Leftover(url: $0, size: CleanScanner.size($0)) }
    }
}

@MainActor
final class LargeFiles: ObservableObject {
    struct Item: Identifiable {
        let url: URL
        let size: Int64
        let installer: Bool
        var id: URL { url }
    }

    @Published private(set) var items: [Item] = []
    @Published private(set) var scanning = false
    @Published private(set) var scanned = false

    var total: Int64 { items.reduce(0) { $0 + $1.size } }

    func scan() {
        guard !scanning else { return }
        scanning = true
        Task {
            items = await Task.detached(priority: .userInitiated) { Self.find() }.value
            scanning = false
            scanned = true
        }
    }

    func trash(_ item: Item) {
        if (try? FileManager.default.trashItem(at: item.url, resultingItemURL: nil)) != nil {
            items.removeAll { $0.id == item.id }
        }
    }

    // Files of 500 MB or more, plus installers left in Downloads.
    nonisolated private static func find() -> [Item] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let downloads = home.appendingPathComponent("Downloads").path
        let installerTypes: Set = ["dmg", "pkg", "iso", "xip"]
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        var found: [Item] = []
        for name in ["Downloads", "Desktop", "Documents", "Movies"] {
            guard let e = fm.enumerator(at: home.appendingPathComponent(name), includingPropertiesForKeys: Array(keys),
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
                let size = Int64(v.totalFileAllocatedSize ?? 0)
                let installer = url.path.hasPrefix(downloads) && installerTypes.contains(url.pathExtension.lowercased())
                if size >= 500_000_000 || (installer && size >= 1_000_000) {
                    found.append(Item(url: url, size: size, installer: installer))
                }
            }
        }
        return Array(found.sorted { $0.size > $1.size }.prefix(60))
    }
}
