import SwiftUI

// Ask a local model, or see what AI coding tools have used.
struct AIView: View {
    @State private var page = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Segmented(options: ["Ask", "Usage"], selection: $page).fixedSize()
            if page == 0 { AskView() } else { FitOrScroll { UsageView() } }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// Today, the last five hours and the week for each AI coding tool found on this Mac.
private struct UsageView: View {
    @EnvironmentObject var usage: AIUsage
    @EnvironmentObject var settings: Settings

    private var claude: AIUsage.Provider? { usage.providers.first { $0.id == "claude" } }
    private var codex: AIUsage.Provider? { usage.providers.first { $0.id == "codex" } }

    var body: some View {
        Group {
            // The first read goes through every log of the past week, which takes a moment.
            if usage.providers.isEmpty {
                LoadingView(text: "Reading Claude Code and Codex logs…").frame(minHeight: 160)
            } else {
                content
            }
        }
        .onAppear { usage.setActive(true) }
        .onDisappear { usage.setActive(false) }
    }

    private var content: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                StatCell(label: "Today", color: Theme.accent, value: money(claude?.today.cost),
                         caption: "\(tokens(totalToday)) tokens · API rates")
                divider
                StatCell(label: "Last 5 hours", color: Theme.accent2, value: tokens(claude.map { $0.window.tokens + (codex?.window.tokens ?? 0) }),
                         caption: "\((claude?.window.requests ?? 0) + (codex?.window.requests ?? 0)) requests")
                divider
                StatCell(label: "This week", color: Theme.amber, value: money(claude?.week.cost),
                         caption: "\(tokens((claude?.week.tokens ?? 0) + (codex?.week.tokens ?? 0))) tokens")
                divider
                if let limit = codex?.limits.max(by: { $0.percent < $1.percent }) {
                    StatCell(label: "Codex \(limit.label.lowercased())", color: Theme.level(limit.percent / 100),
                             value: "\(Int(limit.percent.rounded()))%", caption: limit.resets.map { "Resets \($0.formatted(.relative(presentation: .named)))" } ?? "used")
                } else {
                    StatCell(label: "Requests today", color: Theme.good, value: "\((claude?.today.requests ?? 0) + (codex?.today.requests ?? 0))",
                             caption: "Claude Code + Codex")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .card()

            HStack(alignment: .top, spacing: 10) {
                ClaudeCard(provider: claude)
                ToolsCard(codex: codex).frame(width: settings.size == .compact ? 200 : 236)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var totalToday: Int { (claude?.today.tokens ?? 0) + (codex?.today.tokens ?? 0) }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(width: 1).padding(.vertical, 1)
    }
}

func tokens(_ n: Int?) -> String {
    guard let n, n > 0 else { return "0" }
    return n.formatted(.number.notation(.compactName).precision(.significantDigits(3)))
}

func money(_ value: Double?) -> String {
    guard let value, value > 0 else { return "$0" }
    return value < 10 ? String(format: "$%.2f", value) : "$" + Int(value.rounded()).formatted()
}

private struct ClaudeCard: View {
    let provider: AIUsage.Provider?
    @State private var hovered: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code").font(.app(size: 13, weight: .semibold))
                    Text(provider?.detected == true ? "From ~/.claude logs · what the tokens would cost on the API"
                         : "Not found on this Mac").font(.app(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
                }
                Spacer()
                if let provider, let i = hovered {
                    Text("\(dayLabel(i)) · \(money(provider.days[i]))").font(.mono(size: 9, weight: .semibold)).foregroundStyle(Theme.dim)
                }
            }
            if let provider, provider.detected {
                HStack(alignment: .bottom, spacing: 12) {
                    bars(provider.days)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(provider.models.prefix(3), id: \.name) { model in
                            HStack(spacing: 6) {
                                Text(model.name).font(.app(size: 10, weight: .medium)).lineLimit(1)
                                Spacer(minLength: 4)
                                Text(tokens(model.totals.tokens)).font(.mono(size: 9)).foregroundStyle(Theme.faint)
                                Text(money(model.totals.cost)).font(.mono(size: 9.5, weight: .semibold)).frame(width: 50, alignment: .trailing)
                            }
                        }
                        if provider.models.isEmpty {
                            Text("Nothing used today").font(.app(size: 9.5)).foregroundStyle(Theme.faint)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    // One bar per day, oldest first, today in full accent; hover shows the day's figure above.
    private func bars(_ days: [Double]) -> some View {
        let top = max(days.max() ?? 0, 0.01)
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(days.indices, id: \.self) { i in
                VStack(spacing: 3) {
                    UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4, style: .continuous)
                        .fill(Theme.accent.opacity(i == 6 || hovered == i ? 1 : 0.45))
                        .frame(width: 14, height: max(2, 64 * days[i] / top))
                        .frame(height: 64, alignment: .bottom)
                    Text(String(dayLabel(i).prefix(1))).font(.app(size: 8, weight: .semibold))
                        .foregroundStyle(i == 6 ? Theme.ink : Theme.faint)
                }
                .padding(.horizontal, 2)
                .contentShape(Rectangle())
                .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
            }
        }
    }

    private func dayLabel(_ i: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: i - 6, to: Date()) ?? Date()
        return i == 6 ? "Today" : date.formatted(.dateTime.weekday(.abbreviated))
    }
}

// Codex from its own logs; tools that keep usage only behind their sign-in are listed as such.
private struct ToolsCard: View {
    let codex: AIUsage.Provider?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Other tools").font(.app(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Codex").font(.app(size: 10.5, weight: .medium))
                    Spacer()
                    Text(codex?.detected == true ? "\(tokens(codex?.today.tokens)) today" : "Not found")
                        .font(.mono(size: 9)).foregroundStyle(Theme.faint)
                }
                ForEach(codex?.limits ?? [], id: \.label) { limit in
                    HStack(spacing: 6) {
                        Text(limit.label).font(.app(size: 9)).foregroundStyle(Theme.dim).frame(width: 64, alignment: .leading)
                        SegmentMeter(value: limit.percent / 100, color: Theme.level(limit.percent / 100), segments: 16)
                        Text("\(Int(limit.percent.rounded()))%").font(.mono(size: 9)).frame(width: 30, alignment: .trailing)
                    }
                }
            }
            Rectangle().fill(Theme.stroke).frame(height: 1)
            ForEach(["Cursor", "Antigravity", "Gemini CLI"], id: \.self) { name in
                HStack {
                    Text(name).font(.app(size: 10.5, weight: .medium))
                    Spacer()
                    Text(Self.installed(name) ? "Usage kept online" : "Not found")
                        .font(.app(size: 9)).foregroundStyle(Theme.faint)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private static func installed(_ name: String) -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch name {
        case "Cursor": return FileManager.default.fileExists(atPath: "/Applications/Cursor.app")
        case "Antigravity": return FileManager.default.fileExists(atPath: "/Applications/Antigravity.app")
        default: return FileManager.default.fileExists(atPath: home + "/.gemini/tmp")
        }
    }
}

// One question at a time to the chosen model, with Claude Code's live sessions beside it.
private struct AskView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var claude: ClaudeBridge
    @EnvironmentObject var model: AppModel
    @State private var question = ""
    @State private var answer: AIResult?
    // What a file dropped on Ask AI says, once read; nil while reading.
    @State private var fileText: String?
    @FocusState private var focused: Bool

    private var engine: Assistant.Engine { Assistant.Engine(rawValue: settings.aiEngine) ?? .onDevice }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.accent)
                    TextField(model.aiFile == nil ? "Ask anything, then press Return" : "Ask about this file, then press Return", text: $question)
                        .textFieldStyle(.plain).font(.app(size: 11.5)).focused($focused)
                        .onSubmit(send)
                    Menu {
                        ForEach(Assistant.Engine.allCases) { option in
                            Button { settings.aiEngine = option.rawValue } label: {
                                Text(option.title + (Assistant.available(option) ? "" : " (not found)"))
                            }
                            .disabled(!Assistant.available(option))
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(engine.title).font(.app(size: 9.5, weight: .semibold))
                            Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold))
                        }
                        .foregroundStyle(Theme.dim)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(RoundedRectangle(cornerRadius: Theme.round(9), style: .continuous).fill(Theme.ink.opacity(0.06)))
                if let file = model.aiFile { fileBar(file) }

                Group {
                    if let answer {
                        if let text = answer.text {
                            ScrollView {
                                Text(text).font(.app(size: 11.5)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .scrollIndicators(.never)
                        } else if let error = answer.error {
                            Text(error).font(.app(size: 10.5)).foregroundStyle(Theme.amber)
                        } else {
                            LoadingView(text: "\(engine.title) is thinking…")
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(engine == .onDevice ? "Answers come from Apple's on-device model: private, offline and free."
                                 : engine == .claude ? "Answers come from Claude Code on this Mac, with your Claude plan."
                                 : "Answers come from the first model Ollama has pulled.")
                                .font(.app(size: 10)).foregroundStyle(Theme.faint)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if let text = answer?.text {
                    HStack {
                        Spacer()
                        PillButton(text: "Copy answer", icon: "doc.on.doc", color: Theme.accent) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .card()

            SessionsCard().frame(width: settings.size == .compact || settings.size == .mini ? 190 : 220)
        }
        .onAppear { focused = true }
        .task(id: model.aiFile) {
            fileText = nil
            answer = nil
            guard let file = model.aiFile else { return }
            fileText = await Assistant.contents(of: file)
        }
    }

    // The dropped file, and what to do with it.
    private func fileBar(_ file: URL) -> some View {
        HStack(spacing: 6) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().frame(width: 18, height: 18)
            Text(file.lastPathComponent).font(.app(size: 10, weight: .semibold)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 4)
            if fileText == nil {
                ProgressView().controlSize(.small)
                Text("Reading…").font(.app(size: 9)).foregroundStyle(Theme.faint)
            } else if fileText?.isEmpty == true {
                Text("No text found in this file").font(.app(size: 9)).foregroundStyle(Theme.amber)
            } else {
                PillButton(text: "Summarize", color: Theme.accent) { run(.summarize) }
                PillButton(text: "Translate", color: Theme.accent) {
                    run(Locale.current.language.languageCode?.identifier == "id" ? .indonesian : .english)
                }
                PillButton(text: "Text", color: Theme.accent) {
                    answer = AIResult(id: UUID(), title: "Text", text: fileText, error: nil)
                }
            }
            IconButton(icon: "xmark") { model.aiFile = nil }.help("Put the file away")
        }
    }

    private func run(_ action: TextAction) {
        guard let content = fileText, !content.isEmpty else { return }
        ask(String(content.prefix(12000)), instructions: action.instructions, title: action.title)
    }

    private func send() {
        let text = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let content = fileText, !content.isEmpty, let file = model.aiFile {
            ask("File \(file.lastPathComponent):\n\(content.prefix(12000))\n\nQuestion: \(text)",
                instructions: "Answer the question about the file helpfully and briefly, in the language of the question.", title: text)
        } else {
            ask(text, instructions: "Answer helpfully and briefly, in the language of the question.", title: text)
        }
    }

    private func ask(_ prompt: String, instructions: String, title: String) {
        let ticket = UUID()
        answer = AIResult(id: ticket, title: title, text: nil, error: nil)
        let engine = engine
        Task {
            do {
                let reply = try await Assistant.respond(prompt, instructions: instructions, engine: engine)
                if answer?.id == ticket { answer?.text = reply }
            } catch {
                if answer?.id == ticket { answer?.error = error.localizedDescription }
            }
        }
    }
}

private struct SessionsCard: View {
    @EnvironmentObject var claude: ClaudeBridge
    @EnvironmentObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Code").font(.app(size: 12, weight: .semibold))
            if !settings.claudeBridge {
                Text("Turn on Claude Code in the notch (Settings › AI) to see sessions here and approve requests from the notch.")
                    .font(.app(size: 9.5)).foregroundStyle(Theme.faint)
                PillButton(text: "Turn on", color: Theme.accent) { settings.claudeBridge = true }
            } else if claude.sessions.isEmpty {
                Text("Start Claude Code in any terminal; its sessions show here.").font(.app(size: 9.5)).foregroundStyle(Theme.faint)
            } else {
                ForEach(claude.sessions) { session in
                    HStack(spacing: 7) {
                        Circle().fill(color(session.state)).frame(width: 6, height: 6)
                        Text(session.project).font(.app(size: 10.5, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text(label(session.state)).font(.app(size: 9)).foregroundStyle(Theme.faint)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private func color(_ state: ClaudeBridge.Session.State) -> Color {
        switch state { case .working: Theme.accent; case .waiting: Theme.amber; case .done: Theme.faint }
    }

    private func label(_ state: ClaudeBridge.Session.State) -> String {
        switch state { case .working: "Working"; case .waiting: "Waiting for you"; case .done: "Done" }
    }
}
