import SwiftUI

// Copied things on one side, a scratchpad on the other.
struct ClipboardView: View {
    @State private var mode = 0

    var body: some View {
        VStack(spacing: 8) {
            if mode == 0 {
                HistoryView(mode: $mode)
            } else {
                NotesView(mode: $mode)
            }
        }
    }
}

private struct HistoryView: View {
    @EnvironmentObject var clipboard: ClipboardHistory
    @EnvironmentObject var model: AppModel
    @Binding var mode: Int
    @State private var result: AIResult?
    @State private var query = ""
    @State private var copied: UUID?
    @State private var selected = 0

    private var filtered: [ClipEntry] {
        guard !query.isEmpty else { return clipboard.sorted }
        return clipboard.sorted.filter { ClipboardHistory.matches($0.searchable, query) }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Segmented(options: ["History", "Notes"], selection: $mode).fixedSize()
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
                    TextField("Search text, file names, or words in images", text: $query)
                        .textFieldStyle(.plain)
                        .font(.app(size: 11))
                        .onChange(of: query) { _, _ in selected = 0 }
                        // ↑ ↓ to move through the list, Return to copy, without leaving the search field.
                        .onKeyPress(.downArrow) { move(1) }
                        .onKeyPress(.upArrow) { move(-1) }
                        .onSubmit { copySelected() }
                }
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.ink.opacity(0.06)))
                Pill(text: "\(clipboard.entries.count) items")
                PillButton(text: "Clear") { clipboard.clear() }
            }

            if !clipboard.enabled {
                Placeholder(icon: "doc.on.clipboard", title: "Clipboard history is off", caption: "Turn it on in Settings")
            } else if filtered.isEmpty {
                Placeholder(icon: "doc.on.clipboard", title: query.isEmpty ? "Nothing copied yet" : "No match",
                            caption: "Text, images and files you copy show up here")
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 3) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, entry in
                                row(entry, active: index == selected).id(entry.id)
                            }
                        }
                    }
                    .onChange(of: selected) { _, index in
                        if filtered.indices.contains(index) { proxy.scrollTo(filtered[index].id) }
                    }
                }
            }

            Text("↑ ↓ and Return in the search field, or click · ✦ on text to summarize, translate or fix it")
                .font(.app(size: 8.5)).foregroundStyle(Theme.faint)
        }
        .overlay(alignment: .bottom) {
            if let result {
                AIResultCard(result: result, engine: model.engine.title) { self.result = nil }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.25), value: result)
    }

    private func move(_ step: Int) -> KeyPress.Result {
        guard !filtered.isEmpty else { return .ignored }
        selected = min(max(selected + step, 0), filtered.count - 1)
        return .handled
    }

    private func copySelected() {
        guard filtered.indices.contains(selected) else { return }
        clipboard.copy(filtered[selected])
        copied = filtered[selected].id
    }

    private func row(_ entry: ClipEntry, active: Bool) -> some View {
        HStack(spacing: 8) {
            sourceIcon(entry.source)
            switch entry.content {
            case .text(let text):
                Text(text.replacingOccurrences(of: "\n", with: " ")).font(.app(size: 10.5)).lineLimit(1)
            case .image(let image, _):
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 24, height: 18).clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 0) {
                    Text("Image · \(Int(image.size.width))×\(Int(image.size.height))").font(.app(size: 10.5))
                    if let words = entry.recognized {
                        Text(words).font(.app(size: 8.5)).foregroundStyle(Theme.faint).lineLimit(1)
                    }
                }
            case .files(let urls):
                Image(nsImage: NSWorkspace.shared.icon(forFile: urls[0].path)).resizable().frame(width: 18, height: 18)
                Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls[0].lastPathComponent) + \(urls.count - 1) more")
                    .font(.app(size: 10.5)).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if let text = entry.text { aiMenu(text) }
            if copied == entry.id {
                Pill(text: "Copied", color: Theme.accent, icon: "checkmark")
            } else {
                Text(entry.date.formatted(.relative(presentation: .numeric)))
                    .font(.mono(size: 8.5)).foregroundStyle(Theme.faint)
            }
            Button { clipboard.togglePin(entry) } label: {
                Image(systemName: entry.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(entry.pinned ? Theme.amber : Theme.faint)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(active ? Theme.accent.opacity(0.14) : Theme.ink.opacity(entry.pinned ? 0.08 : 0.045)))
        .contentShape(Rectangle())
        .onTapGesture {
            clipboard.copy(entry)
            copied = entry.id
        }
    }

    private func aiMenu(_ text: String) -> some View {
        Menu {
            ForEach(TextAction.allCases) { action in
                Button { run(action, on: text) } label: { Label(action.title, systemImage: action.icon) }
            }
        } label: {
            Image(systemName: "sparkles").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 20, height: 20).contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Summarize, translate, fix or explain with \(model.engine.title)")
    }

    private func run(_ action: TextAction, on text: String) {
        let ticket = UUID()
        result = AIResult(id: ticket, title: action.title, text: nil, error: nil)
        let engine = model.engine
        Task {
            do {
                let answer = try await Assistant.respond(String(text.prefix(6000)), instructions: action.instructions, engine: engine)
                if result?.id == ticket { result?.text = answer }
            } catch {
                if result?.id == ticket { result?.error = error.localizedDescription }
            }
        }
    }

    @ViewBuilder private func sourceIcon(_ bundleID: String?) -> some View {
        if let bundleID, let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 16, height: 16)
                .help(FileManager.default.displayName(atPath: url.path))
        } else {
            Image(systemName: "doc.on.clipboard").font(.system(size: 10)).foregroundStyle(Theme.dim).frame(width: 16)
        }
    }
}

private struct NotesView: View {
    @EnvironmentObject var notes: Notes
    @EnvironmentObject var shelf: Shelf
    @EnvironmentObject var model: AppModel
    @Binding var mode: Int

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Segmented(options: ["History", "Notes"], selection: $mode).fixedSize()
                Spacer()
                Pill(text: "\(notes.text.split(whereSeparator: \.isWhitespace).count) words")
                PillButton(text: "Copy", icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(notes.text, forType: .string)
                }
                PillButton(text: "To Shelf", icon: "tray.and.arrow.down", color: Theme.accent) {
                    if let url = notes.exportFile() {
                        shelf.add([url])
                        model.show(Notice(icon: "note.text", color: Theme.accent, left: "Note", right: "On the Shelf"))
                    }
                }
                PillButton(text: "Clear", color: Theme.red) { notes.text = "" }
            }
            TextEditor(text: $notes.text)
                .font(.app(size: 11.5))
                .scrollContentBackground(.hidden)
                .scrollIndicators(.never)
                .padding(8)
                .card()
                .overlay(alignment: .topLeading) {
                    if notes.text.isEmpty {
                        Text("Jot something down. It's saved as you type.")
                            .font(.app(size: 11.5)).foregroundStyle(Theme.faint)
                            .padding(.horizontal, 13).padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
        }
    }
}

struct AIResult: Equatable {
    let id: UUID
    let title: String
    var text: String?
    var error: String?
}

// The answer to a clipboard action, over the bottom of the list.
struct AIResultCard: View {
    let result: AIResult
    let engine: String
    var close: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                Text(result.title).font(.app(size: 11, weight: .semibold))
                Text(engine).font(.app(size: 9)).foregroundStyle(Theme.faint)
                Spacer()
                if let text = result.text {
                    PillButton(text: copied ? "Copied" : "Copy", icon: copied ? "checkmark" : "doc.on.doc", color: Theme.accent) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                        copied = true
                    }
                }
                IconButton(icon: "xmark") { close() }
            }
            if let text = result.text {
                ScrollView { Text(text).font(.app(size: 11)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 110)
            } else if let error = result.error {
                Text(error).font(.app(size: 10)).foregroundStyle(Theme.amber)
            } else {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Thinking…").font(.app(size: 10)).foregroundStyle(Theme.dim) }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.background))
        .card()
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
    }
}
