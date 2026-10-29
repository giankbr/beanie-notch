import SwiftUI

// A rough 0–100: a nearly full disk, memory pressure and piled-up junk each cost points.
@MainActor
func healthScore(_ stats: SystemStats, _ cleaner: Cleaner) -> Int {
    var s = 100.0
    s -= max(0, stats.disk - 0.75) * 160
    s -= max(0, stats.ram - 0.8) * 100
    s -= min(25, Double(cleaner.total) / 1_000_000_000 * 5)
    return Int(min(100, max(0, s)).rounded())
}

struct HomeView: View {
    @EnvironmentObject var settings: Settings

    // Scrolls when the panel is too short for it (Compact), instead of squeezing the rows.
    var body: some View {
        if settings.layout == .classic {
            ClassicHome()
        } else {
            dashboard
        }
    }

    private var dashboard: some View {
        ScrollView {
            VStack(spacing: 10) {
                StatStrip()
                HStack(alignment: .top, spacing: 10) {
                    CleanupCard().frame(maxHeight: .infinity, alignment: .top)
                    QuickSettingsCard()
                        .frame(width: settings.compactPages ? 190 : 220)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .scrollIndicators(.never)
    }
}

private struct StatStrip: View {
    @EnvironmentObject var stats: SystemStats
    @EnvironmentObject var cleaner: Cleaner

    var body: some View {
        let score = healthScore(stats, cleaner)
        HStack(spacing: 0) {
            cell("Health", color: score >= 80 ? Theme.good : score >= 60 ? Theme.amber : Theme.red,
                 value: "\(score)", caption: score >= 80 ? "Running smooth" : score >= 60 ? "Could use a tidy-up" : "Needs attention")
            divider
            cell("CPU", color: Theme.level(stats.cpu), value: "\(Int(stats.cpu * 100))%",
                 caption: stats.temperature.map { "\($0) °C" } ?? "All cores")
            divider
            cell("Memory", color: Theme.level(stats.ram), value: formatMemory(stats.ramUsed),
                 caption: "of \(formatMemory(stats.ramTotal))")
            divider
            cell("Network", color: Theme.accent2, value: "↓ " + formatRate(stats.download),
                 caption: "↑ " + formatRate(stats.upload))
            divider
            cell("Disk", color: Theme.level(stats.disk), value: "\(Int(stats.disk * 100))%",
                 caption: stats.diskFree > 0 ? "\(formatBytes(stats.diskFree)) free" : "used")
        }
        .background(RoundedRectangle(cornerRadius: Theme.round(12), style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.round(12), style: .continuous).strokeBorder(Theme.stroke))
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(width: 1).padding(.vertical, 1)
    }

    private func cell(_ label: String, color: Color, value: String, caption: String) -> some View {
        StatCell(label: label, color: color, value: value, caption: caption)
    }
}

struct CardHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(size: 13, weight: .semibold))
                Text(subtitle).font(.app(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            Spacer(minLength: 6)
            trailing
        }
    }
}

private struct CleanupCard: View {
    @EnvironmentObject var cleaner: Cleaner
    @EnvironmentObject var largeFiles: LargeFiles
    @EnvironmentObject var model: AppModel

    private var subtitle: String {
        guard let last = cleaner.history.last else { return "Sorted by size · never cleaned" }
        return "Sorted by size · last run \(last.date.formatted(.relative(presentation: .named)))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardHeader(title: "Cleanup", subtitle: subtitle) {
                Button { cleaner.clean(.all) } label: {
                    Text(cleaner.cleaning != nil ? "Cleaning \(Int(cleaner.progress * 100))%" : "Free \(formatBytes(cleaner.total))")
                        .font(.app(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.background)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .buttonFace(Capsule(), Theme.ink)
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(cleaner.cleaning != nil || cleaner.total == 0)
                .opacity(cleaner.total == 0 ? 0.5 : 1)
            }
            .padding(.bottom, 2)

            row(bar: Theme.amber, title: "Temp & junk", tag: "Reclaimable", tagColor: Theme.amber,
                detail: "Caches, logs and temp files older than a day", figure: formatBytes(cleaner.tempBytes),
                busy: cleaner.cleaning == .temp || cleaner.cleaning == .all, action: "Clean", enabled: cleaner.tempBytes > 0) {
                cleaner.clean(.temp)
            }
            Divider().overlay(Theme.stroke)
            row(bar: Theme.accent2, title: "Browser cache",
                tag: cleaner.browsers.isEmpty ? nil : cleaner.browsers.prefix(2).joined(separator: " · "), tagColor: Theme.accent2,
                detail: "Web pages and images saved by browsers", figure: formatBytes(cleaner.browserBytes),
                busy: cleaner.cleaning == .browser || cleaner.cleaning == .all, action: "Clean", enabled: cleaner.browserBytes > 0) {
                cleaner.clean(.browser)
            }
            Divider().overlay(Theme.stroke)
            row(bar: Theme.red, title: "Large files", tag: largeFiles.scanned ? "\(largeFiles.items.count) found" : nil,
                tagColor: Theme.red, detail: "500 MB and up, plus old installers in Downloads",
                figure: largeFiles.scanned ? formatBytes(largeFiles.total) : nil,
                busy: largeFiles.scanning, action: largeFiles.scanned ? "Review" : "Scan", enabled: true) {
                if !largeFiles.scanned { largeFiles.scan() }
                model.openSettings(.tools)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.round(12), style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.round(12), style: .continuous).strokeBorder(Theme.stroke))
    }

    private func row(bar: Color, title: String, tag: String?, tagColor: Color, detail: String, figure: String?,
                     busy: Bool, action: String, enabled: Bool, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Capsule().fill(bar).frame(width: 3, height: 28)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title).font(.app(size: 11, weight: .medium)).lineLimit(1).fixedSize()
                    if let tag { Pill(text: tag, color: tagColor).layoutPriority(-1) }
                }
                Text(detail).font(.app(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            Spacer(minLength: 6)
            if let figure {
                Text(figure)
                    .font(.mono(size: 9.5))
                    .fixedSize()
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: Theme.round(6), style: .continuous).fill(Theme.ink.opacity(0.06)))
            }
            if busy {
                ProgressView().controlSize(.small).frame(width: 52)
            } else {
                Button(action: perform) {
                    Text(action)
                        .font(.app(size: 9.5, weight: .medium))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .buttonFace(Capsule(), Theme.ink.opacity(0.09))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.4)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct QuickSettingsCard: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var clipboard: ClipboardHistory

    private var onCount: Int {
        [clipboard.enabled, settings.screenshotsToShelf, settings.lyrics].filter { $0 }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CardHeader(title: "Quick settings", subtitle: "3 switches · \(onCount) on") { EmptyView() }
                .padding(.bottom, 4)
            toggle("Clipboard history", "100 items · memory", $clipboard.enabled)
            toggle("Screenshots to Shelf", "desktop -> shelf", $settings.screenshotsToShelf)
            toggle("Lyrics", "4 free sources", $settings.lyrics)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Theme.round(12), style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.round(12), style: .continuous).strokeBorder(Theme.stroke))
    }

    private func toggle(_ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.app(size: 11, weight: .medium)).lineLimit(1)
                    .foregroundStyle(isOn.wrappedValue ? Theme.ink : Theme.dim)
                Text(detail).font(.mono(size: 8.5, weight: .regular)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: isOn).toggleStyle(AccentSwitchStyle()).labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
