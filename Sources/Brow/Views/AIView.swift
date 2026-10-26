import SwiftUI

// Today, the last five hours and the week for each AI coding tool found on this Mac.
struct AIView: View {
    @EnvironmentObject var usage: AIUsage
    @EnvironmentObject var settings: Settings

    private var claude: AIUsage.Provider? { usage.providers.first { $0.id == "claude" } }
    private var codex: AIUsage.Provider? { usage.providers.first { $0.id == "codex" } }

    var body: some View {
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
        .onAppear { usage.setActive(true) }
        .onDisappear { usage.setActive(false) }
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
