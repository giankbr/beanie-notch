import SwiftUI

struct ToolsView: View {
    @EnvironmentObject var uninstaller: Uninstaller
    @EnvironmentObject var largeFiles: LargeFiles
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Segmented(options: ["Uninstaller", "Large files", "Mirror"], selection: $mode)
                Spacer()
                if mode == 0 {
                    if let message = uninstaller.message { Pill(text: message, color: Theme.amber) }
                    PillButton(text: "Refresh", icon: "arrow.clockwise") { Task { await uninstaller.loadApps(force: true) } }
                } else if largeFiles.scanned {
                    Pill(text: "\(largeFiles.items.count) files · \(formatBytes(largeFiles.total))")
                    PillButton(text: "Rescan", icon: "arrow.clockwise") { largeFiles.scan() }
                }
            }
            switch mode {
            case 0: UninstallerView()
            case 1: LargeFilesView()
            default:
                CameraMirror()
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Pill(text: "Camera on while this shows", color: .white, dot: true).padding(10)
                    }
            }
        }
    }
}

private struct UninstallerView: View {
    @EnvironmentObject var uninstaller: Uninstaller
    @State private var query = ""

    private var filtered: [Uninstaller.AppInfo] {
        query.isEmpty ? uninstaller.apps : uninstaller.apps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(spacing: 10) {
            VStack(spacing: 6) {
                SearchField(placeholder: "Search apps", text: $query)
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { app in
                            let active = uninstaller.selected == app
                            HStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 18, height: 18)
                                Text(app.name).font(.app(size: 10.5, weight: active ? .semibold : .regular)).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(active ? Theme.accent.opacity(0.14) : .clear))
                            .contentShape(Rectangle())
                            .onTapGesture { uninstaller.select(app) }
                        }
                    }
                }
            }
            .frame(width: 200)

            Panel {
                if let app = uninstaller.selected {
                    detail(app)
                } else {
                    Placeholder(icon: "shippingbox", title: "Pick an app",
                                caption: "Brow finds the caches, preferences and support files it leaves behind")
                }
            }
        }
        .task { await uninstaller.loadApps() }
    }

    private func detail(_ app: Uninstaller.AppInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(app.name).font(.app(size: 13, weight: .bold)).lineLimit(1)
                    Text([app.version, app.bundleID].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.app(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
                }
            }
            if uninstaller.loading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 3) {
                        fileRow(app.url, uninstaller.appSize)
                        ForEach(uninstaller.leftovers) { fileRow($0.url, $0.size, admin: $0.needsAdmin) }
                    }
                }
                HStack {
                    Text("\(uninstaller.leftovers.count + 1) items · \(formatBytes(uninstaller.total))")
                        .font(.app(size: 10, weight: .semibold))
                    Spacer()
                    OutlineButton(text: uninstaller.confirming ? "Confirm: move to Trash" : "Move to Trash",
                                  color: uninstaller.confirming ? Theme.red : Theme.accent2) { uninstaller.trash() }
                }
            }
        }
    }

    private func fileRow(_ url: URL, _ size: Int64, admin: Bool = false) -> some View {
        HStack(spacing: 5) {
            if admin {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: {
                    Image(systemName: "lock.fill").font(.system(size: 8)).foregroundStyle(Theme.amber)
                }
                .buttonStyle(.plain)
                .help("Mac-wide: needs an administrator to remove. Click to show it in Finder.")
            }
            Text(shortPath(url)).font(.app(size: 9)).foregroundStyle(Theme.dim).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(formatBytes(size)).font(.app(size: 9, weight: .semibold)).monospacedDigit()
        }
    }
}

private struct LargeFilesView: View {
    @EnvironmentObject var largeFiles: LargeFiles

    var body: some View {
        if largeFiles.scanning {
            Placeholder(icon: "magnifyingglass", title: "Scanning…", caption: "Downloads, Desktop, Documents and Movies")
        } else if !largeFiles.scanned {
            Placeholder(icon: "externaldrive", title: "Find what takes the space",
                        caption: "Files of 500 MB or more, and installers left in Downloads") {
                PrimaryButton(text: "Scan", icon: "magnifyingglass") { largeFiles.scan() }.frame(width: 140)
            }
        } else if largeFiles.items.isEmpty {
            Placeholder(icon: "checkmark.circle", title: "Nothing big here", caption: "No file of 500 MB or more, no installers left")
        } else {
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(largeFiles.items) { item in
                        HStack(spacing: 8) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path)).resizable().frame(width: 22, height: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.url.lastPathComponent).font(.app(size: 10.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                                Text(shortPath(item.url.deletingLastPathComponent())).font(.app(size: 8.5)).foregroundStyle(Theme.faint).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            if item.installer { Pill(text: "Installer", color: Theme.amber) }
                            Text(formatBytes(item.size)).font(.app(size: 11, weight: .bold)).monospacedDigit()
                            IconButton(icon: "magnifyingglass") { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }.help("Show in Finder")
                            IconButton(icon: "trash") { largeFiles.trash(item) }.help("Move to Trash")
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.surface))
                    }
                }
            }
        }
    }
}
