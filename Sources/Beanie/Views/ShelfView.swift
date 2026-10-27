import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

struct ShelfView: View {
    @EnvironmentObject var shelf: Shelf
    @EnvironmentObject var model: AppModel
    @State private var phone = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Pill(text: "Drop & drag out", color: Theme.accent2, icon: "bolt.fill")
                Pill(text: "\(shelf.items.count) file\(shelf.items.count == 1 ? "" : "s")")
                Spacer()
                IconButton(icon: "square.grid.2x2", active: shelf.grid) { shelf.grid = true }
                IconButton(icon: "list.bullet", active: !shelf.grid) { shelf.grid = false }
                PillButton(text: phone ? "Done" : "From phone", icon: "iphone", color: Theme.accent) { phone.toggle() }
                PillButton(text: "Add Files", icon: "plus", color: Theme.accent2) { shelf.pickFiles() }
                if !shelf.items.isEmpty {
                    PillButton(text: "AirDrop all", icon: "dot.radiowaves.left.and.right", color: Theme.accent2) {
                        shelf.airDrop(shelf.items)
                    }
                }
                PillButton(text: "Clear All") { shelf.clear() }
            }

            if phone {
                PhoneDropPanel()
            } else {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.ink.opacity(0.04))
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(model.dropTargeted ? Theme.accent : Theme.stroke,
                                  style: StrokeStyle(lineWidth: model.dropTargeted ? 1.5 : 1, dash: model.dropTargeted ? [5, 4] : []))
                if model.dropTargeted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.accent.opacity(0.08))
                }
                if shelf.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 22, weight: .light))
                        Text("Drop files here to keep them handy").font(.app(size: 10, weight: .medium))
                    }
                    .foregroundStyle(Theme.faint)
                } else {
                    ScrollView {
                        if shelf.grid {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], spacing: 8) {
                                ForEach(shelf.items, id: \.self) { ShelfTile(url: $0) }
                            }
                            .padding(8)
                        } else {
                            LazyVStack(spacing: 4) {
                                ForEach(shelf.items, id: \.self) { ShelfRow(url: $0) }
                            }
                            .padding(8)
                        }
                    }
                }
            }
            // While a file is dragged over the panel: the Shelf dims, and its right third becomes the AirDrop target.
            .overlay {
                if model.dropTargeted {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.background.opacity(0.94))
                        HStack {
                            VStack(spacing: 6) {
                                Image(systemName: "tray.and.arrow.down").font(.system(size: 20, weight: .medium))
                                Text("Keep on the Shelf").font(.app(size: 11, weight: .semibold))
                            }
                            .foregroundStyle(model.dropToAirDrop ? Theme.dim : Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            VStack(spacing: 6) {
                                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 20, weight: .medium))
                                Text("AirDrop").font(.app(size: 11, weight: .semibold))
                                Text("Drop here to send").font(.app(size: 9))
                            }
                            .foregroundStyle(model.dropToAirDrop ? Theme.accent2 : Theme.dim)
                            .frame(width: max(120, model.openSize.width * 0.32 - 14))
                            .frame(maxHeight: .infinity)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Theme.accent2.opacity(model.dropToAirDrop ? 0.22 : 0.08)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Theme.accent2.opacity(model.dropToAirDrop ? 0.9 : 0.35), style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                            .padding(6)
                        }
                    }
                    .animation(.easeOut(duration: 0.12), value: model.dropToAirDrop)
                }
            }
            .animation(.easeOut(duration: 0.15), value: model.dropTargeted)
            }
        }
    }
}

private func fileSize(_ url: URL) -> String {
    let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey])
    if values?.isDirectory == true { return "Folder" }
    return formatBytes(Int64(values?.totalFileAllocatedSize ?? 0))
}

private struct ShelfTile: View {
    @EnvironmentObject var shelf: Shelf
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            FileThumb(url: url)
                .frame(height: 62)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .topLeading) {
                    if !url.pathExtension.isEmpty {
                        Pill(text: url.pathExtension.uppercased(), color: .white).padding(4)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    Button { shelf.remove(url) } label: {
                        Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                            .frame(width: 15, height: 15).background(Circle().fill(.black.opacity(0.6)))
                    }
                    .buttonStyle(.plain).padding(4)
                }
            Text(url.lastPathComponent).font(.app(size: 9, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            Text("\(fileSize(url)) • Drag out ready").font(.app(size: 8)).foregroundStyle(Theme.accent2).lineLimit(1)
            HStack(spacing: 4) {
                IconButton(icon: "arrow.up.forward.app") { NSWorkspace.shared.open(url) }.help("Open")
                IconButton(icon: "folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }.help("Show in Finder")
                IconButton(icon: "dot.radiowaves.left.and.right") { shelf.airDrop([url]) }.help("AirDrop")
            }
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Theme.stroke))
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
    }
}

private struct ShelfRow: View {
    @EnvironmentObject var shelf: Shelf
    let url: URL

    var body: some View {
        HStack(spacing: 8) {
            FileThumb(url: url).frame(width: 26, height: 26).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).font(.app(size: 10, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Text(fileSize(url)).font(.app(size: 8.5)).foregroundStyle(Theme.faint)
            }
            Spacer()
            PillButton(text: "Open") { NSWorkspace.shared.open(url) }
            PillButton(text: "Folder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            IconButton(icon: "xmark") { shelf.remove(url) }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.ink.opacity(0.05)))
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
    }
}

struct FileThumb: View {
    let url: URL
    @State private var thumbnail: NSImage?

    var body: some View {
        ZStack {
            Theme.ink.opacity(0.05)
            if let thumbnail {
                Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(6)
            }
        }
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 240, height: 140),
                                                       scale: 2, representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                thumbnail = rep.nsImage
            }
        }
    }
}

private struct PhoneDropPanel: View {
    @EnvironmentObject var drop: PhoneDrop

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white)
                if let qr = drop.qr {
                    Image(nsImage: qr).interpolation(.none).resizable().padding(8)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(width: 150, height: 150)
            VStack(alignment: .leading, spacing: 6) {
                Text("Send from your phone").font(.app(size: 14, weight: .semibold))
                Text("Scan with the phone's camera, on the same Wi-Fi as this Mac. Nothing to install.")
                    .font(.app(size: 10)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                if let url = drop.address {
                    Text(url.absoluteString).font(.mono(size: 9)).foregroundStyle(Theme.faint).textSelection(.enabled)
                }
                if let problem = drop.problem {
                    Text(problem).font(.app(size: 10)).foregroundStyle(Theme.amber)
                }
                Spacer(minLength: 0)
                Text(drop.received == 0 ? "Waiting for files…" : "\(drop.received) received · in Downloads/Beanie")
                    .font(.app(size: 10, weight: .medium)).foregroundStyle(Theme.accent)
                Text("The link stops working when you leave this page.").font(.app(size: 8.5)).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
        .onAppear { drop.start() }
        .onDisappear { drop.stop() }
    }
}
