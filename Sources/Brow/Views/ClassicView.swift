import SwiftUI

// The first Brow look: a greeting on top, a six-card overview, and the tabs as a dock along the bottom.

struct GreetingHeader: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var cleaner: Cleaner
    @EnvironmentObject var prayer: PrayerTimes

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 4..<11: "Good morning"
        case 11..<15: "Good afternoon"
        case 15..<19: "Good evening"
        default: "Good night"
        }
    }

    private var name: String {
        (NSFullUserName().split(separator: " ").first.map(String.init) ?? NSUserName()).capitalized
    }

    var body: some View {
        // One line, so the page under it keeps its height: the greeting on Overview, the page's name elsewhere.
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(model.tab == .home ? "\(greeting), \(name)" : model.tab.title).font(.app(size: 14, weight: .bold)).lineLimit(1)
            Text(Date().formatted(.dateTime.weekday(.wide).month(.wide).day()) + " · " + prayer.hijri)
                .font(.app(size: 9.5, weight: .medium)).foregroundStyle(Theme.faint).lineLimit(1)
            Spacer()
            HStack(spacing: 6) {
                if let next = prayer.next {
                    Pill(text: "\(prayer.label(next)) \(next.time.formatted(date: .omitted, time: .shortened))",
                         color: Theme.accent2, icon: "moon.fill")
                }
                if cleaner.cleaning != nil {
                    Pill(text: "Cleaning \(Int(cleaner.progress * 100))%", color: Theme.accent, icon: "sparkles")
                } else {
                    Pill(text: "\(formatBytes(cleaner.total)) ready", color: Theme.good, dot: true)
                }
            }
        }
    }
}

struct DockBar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var cleaner: Cleaner

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { tab in
                button(tab.icon, tab.title, active: model.tab == tab) {
                    withAnimation(.easeInOut(duration: 0.18)) { model.tab = tab }
                }
            }
            Rectangle().fill(Theme.stroke).frame(width: 1, height: 12).padding(.horizontal, 3)
            button("bolt.fill", "Full clean", active: cleaner.cleaning != nil) { cleaner.clean(.all) }
            button("chevron.up", "Close", active: false) { model.expanded = false }
        }
        .padding(3)
        .background(Capsule().fill(Theme.ink.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Theme.stroke))
    }

    private func button(_ icon: String, _ help: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            TabIcon(name: icon, size: 10, weight: .semibold)
                .foregroundStyle(active ? Theme.ink : Theme.dim)
                .frame(width: 26, height: 20)
                .background(Capsule().fill(Theme.ink.opacity(active ? 0.16 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

struct ClassicHome: View {
    @EnvironmentObject var cleaner: Cleaner
    @EnvironmentObject var stats: SystemStats

    private var lastClean: String {
        guard let last = cleaner.history.last else { return "Run a clean to start" }
        return last.date.formatted(.relative(presentation: .named))
    }

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            GridRow {
                card("trash.fill", "Temp & Junk", tag: "Reclaimable", busy: cleaner.cleaning == .temp || cleaner.cleaning == .all, action: { cleaner.clean(.temp) }) {
                    value(formatBytes(cleaner.tempBytes), "User & system temp files")
                }
                card("globe", "Browser Cache", tag: cleaner.browsers.prefix(2).joined(separator: " · "),
                     busy: cleaner.cleaning == .browser || cleaner.cleaning == .all, action: { cleaner.clean(.browser) }) {
                    value(formatBytes(cleaner.browserBytes), "Web & image cache")
                }
                card("cpu", "System Monitor", tag: "Live", busy: false) {
                    HStack {
                        ring(stats.cpu, "CPU")
                        Spacer(minLength: 0)
                        ring(stats.ram, "RAM")
                        Spacer(minLength: 0)
                        ring(stats.disk, "DISK")
                    }
                }
            }
            GridRow {
                card("clock.arrow.circlepath", "Clean History", tag: "Activity", busy: false) {
                    value(cleaner.history.isEmpty ? "Not yet" : "Optimized", lastClean)
                }
                card("memorychip", "RAM Memory", tag: "\(Int(stats.ram * 100))% in use", busy: false) {
                    VStack(alignment: .leading, spacing: 6) {
                        value(formatMemory(stats.ramUsed), "of \(formatMemory(stats.ramTotal)) total")
                        SegmentMeter(value: stats.ram, color: Theme.level(stats.ram), segments: 16)
                    }
                }
                card("wand.and.stars", "Full System Clean", tag: "1-Click", busy: cleaner.cleaning == .all,
                     action: { cleaner.clean(.all) }) {
                    value(formatBytes(cleaner.total), "Junk & browser cache")
                }
            }
        }
    }

    private func card<Content: View>(_ icon: String, _ title: String, tag: String, busy: Bool,
                                     action perform: (() -> Void)? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 9, weight: .bold))
                Text(title).font(.app(size: 10, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                if !tag.isEmpty { Pill(text: tag, color: busy ? Theme.accent : Theme.dim) }
            }
            Spacer(minLength: 6)
            HStack(alignment: .bottom) {
                content()
                if let perform {
                    Spacer(minLength: 4)
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        OutlineButton(text: "Clean", action: perform)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(busy ? Theme.accent.opacity(0.16) : Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(busy ? Theme.accent.opacity(0.5) : Theme.stroke))
    }

    private func value(_ big: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(big).font(.app(size: 19, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(caption).font(.app(size: 8.5, weight: .medium)).foregroundStyle(Theme.faint).lineLimit(1)
        }
    }

    private func ring(_ value: Double, _ label: String) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(Theme.ink.opacity(0.1), lineWidth: 3.5)
                Circle().trim(from: 0, to: min(max(value, 0), 1))
                    .stroke(Theme.level(value), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int((value * 100).rounded()))%").font(.app(size: 8, weight: .bold))
            }
            .frame(width: 34, height: 34)
            .animation(.easeOut(duration: 0.6), value: value)
            Text(label).font(.app(size: 7.5, weight: .semibold)).foregroundStyle(Theme.faint)
        }
    }
}
