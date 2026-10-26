import SwiftUI

// A strip of the day at a glance (weather, the next event, tasks, focus) over the agenda and the focus timer.
struct TodayView: View {
    @EnvironmentObject var settings: Settings
    @State private var page = 0

    var body: some View {
        VStack(spacing: 10) {
            TodayStrip()
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    CardHeader(title: page == 0 ? "Up next" : "Tasks",
                               subtitle: page == 0 ? "Calendar · next 24 hours" : "End with a time for a reminder") {
                        Segmented(options: ["Agenda", "Tasks"], selection: $page).frame(width: 130)
                    }
                    if page == 0 { CalendarPanel() } else { TasksPanel() }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .card()
                FocusPanel().frame(width: settings.size == .compact ? 190 : 220)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

private struct TodayStrip: View {
    @EnvironmentObject var weather: Weather
    @EnvironmentObject var prayer: PrayerTimes
    @EnvironmentObject var calendar: CalendarFeed
    @EnvironmentObject var tasks: TaskList
    @EnvironmentObject var focus: FocusTimer

    var body: some View {
        HStack(spacing: 0) {
            weatherCell
            divider
            agendaCell
            divider
            let open = tasks.items.filter { !$0.done }
            let due = open.filter { $0.due.map(Calendar.current.isDateInToday) ?? false }.count
            StatCell(label: "Tasks", color: Theme.amber, value: open.isEmpty ? "All done" : "\(open.count) open",
                     caption: due > 0 ? "\(due) due today" : open.isEmpty ? "Nothing on the list" : "None due today")
            divider
            TimelineView(.periodic(from: .now, by: focus.isRunning ? 1 : 3600)) { context in
                StatCell(label: focus.phase == .focus ? "Focus" : "Break", color: Theme.accent2,
                         value: formatClock(focus.left(at: context.date)),
                         caption: focus.isRunning ? "Running" : "Ready · \(FocusTimer.presets[focus.preset].focus)/\(FocusTimer.presets[focus.preset].rest)")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .card()
        .onAppear { weather.refresh(for: prayer.place) }
        .onChange(of: prayer.place) { _, place in weather.refresh(for: place) }
    }

    @ViewBuilder private var weatherCell: some View {
        if let report = weather.report {
            HStack(spacing: 0) {
                StatCell(label: prayer.place?.name ?? "Weather", color: Theme.accent,
                         value: "\(Int(report.temp.rounded()))°",
                         caption: "\(Weather.describe(report.code)) · H \(Int(report.high.rounded()))° L \(Int(report.low.rounded()))°")
                Image(systemName: Weather.symbol(report.code)).symbolRenderingMode(.hierarchical).foregroundStyle(Theme.ink).font(.system(size: 20))
                    .padding(.trailing, 12)
            }
        } else {
            StatCell(label: "Weather", color: Theme.accent, value: "–",
                     caption: prayer.place == nil ? "Set your place in Prayer" : weather.failed ? "Didn't load" : "Loading…")
        }
    }

    @ViewBuilder private var agendaCell: some View {
        if !calendar.authorized {
            StatCell(label: "Next event", color: Theme.accent2, value: "–", caption: "Calendar not connected")
        } else if let next = calendar.items.first {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                StatCell(label: "Next event", color: next.color, value: next.title,
                         caption: next.start <= context.date ? "Now · until \(next.end.formatted(date: .omitted, time: .shortened))"
                            : "\(next.start.formatted(date: .omitted, time: .shortened)) · \(next.start.formatted(.relative(presentation: .named)))")
            }
        } else {
            StatCell(label: "Next event", color: Theme.accent2, value: "Free", caption: "Next 24 hours are clear")
        }
    }

    private var divider: some View {
        Rectangle().fill(Theme.stroke).frame(width: 1).padding(.vertical, 1)
    }
}

private struct TasksPanel: View {
    @EnvironmentObject var tasks: TaskList
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
                TextField("Add a task (Call Budi 15:30)", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.app(size: 11))
                    .onSubmit {
                        tasks.add(draft)
                        draft = ""
                    }
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.ink.opacity(0.06)))

            if tasks.items.isEmpty {
                Text("Type a task above and press Return").font(.app(size: 9.5)).foregroundStyle(Theme.faint).padding(.top, 2)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(tasks.items) { item in
                            HStack(spacing: 8) {
                                Button { tasks.toggle(item) } label: {
                                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 13))
                                        .foregroundStyle(item.done ? Theme.accent : Theme.dim)
                                }
                                .buttonStyle(.plain)
                                Text(item.title).font(.app(size: 11)).strikethrough(item.done)
                                    .foregroundStyle(item.done ? Theme.faint : Theme.ink).lineLimit(1)
                                Spacer(minLength: 6)
                                if let due = item.due {
                                    Text(due.formatted(date: Calendar.current.isDateInToday(due) ? .omitted : .abbreviated, time: .shortened))
                                        .font(.mono(size: 9))
                                        .foregroundStyle(!item.done && due < Date() ? Theme.red : Theme.faint)
                                }
                                Button { tasks.remove(item) } label: {
                                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.faint)
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(height: 26)
                        }
                    }
                }
                .scrollIndicators(.never)
                if tasks.items.contains(where: \.done) {
                    PillButton(text: "Clear done") { tasks.clearDone() }
                }
            }
        }
    }
}

private struct CalendarPanel: View {
    @EnvironmentObject var calendar: CalendarFeed

    var body: some View {
        if !calendar.authorized {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock").font(.system(size: 18)).foregroundStyle(Theme.accent2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Connect your calendar").font(.app(size: 11, weight: .semibold))
                    Text("Join calls in one click, and a heads-up in the notch before they start")
                        .font(.app(size: 9)).foregroundStyle(Theme.faint).lineLimit(2)
                }
                Spacer(minLength: 6)
                if calendar.status == .notDetermined {
                    OutlineButton(text: "Connect", color: Theme.accent2) { calendar.connect() }
                } else {
                    OutlineButton(text: "Allow in Settings", color: Theme.accent2) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                }
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.ink.opacity(0.04)))
        } else if calendar.items.isEmpty {
            Text("Nothing in the next 24 hours").font(.app(size: 10)).foregroundStyle(Theme.faint).padding(.top, 2)
        } else {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(calendar.items) { row($0) }
                }
            }
            .scrollIndicators(.never)
        }
    }

    private func row(_ item: CalendarFeed.Item) -> some View {
        let now = Date()
        let live = item.start <= now && item.end > now
        return HStack(spacing: 10) {
            Capsule().fill(item.color).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.app(size: 11, weight: .semibold)).lineLimit(1)
                Text("\(item.start.formatted(date: .omitted, time: .shortened)) – \(item.end.formatted(date: .omitted, time: .shortened))"
                     + (live ? "" : " · \(item.start.formatted(.relative(presentation: .named)))"))
                    .font(.app(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            Spacer(minLength: 6)
            if live { Pill(text: "Now", color: Theme.accent, dot: true) }
            if item.link != nil {
                OutlineButton(text: "Join", color: Theme.accent2) { calendar.join(item) }
            }
        }
    }
}

private struct FocusPanel: View {
    @EnvironmentObject var focus: FocusTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(focus.phase == .focus ? "Focus" : "Break").font(.app(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 2) {
                    ForEach(FocusTimer.presets.indices, id: \.self) { i in
                        let p = FocusTimer.presets[i]
                        Button { focus.choose(i) } label: {
                            Text("\(p.focus)/\(p.rest)")
                                .font(.mono(size: 8.5, weight: .semibold))
                                .foregroundStyle(focus.preset == i ? Theme.ink : Theme.faint)
                                .padding(.horizontal, 5)
                                .frame(height: 18)
                                .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(focus.preset == i ? Theme.ink.opacity(0.1) : .clear))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            TimelineView(.periodic(from: .now, by: focus.isRunning ? 1 : 3600)) { context in
                let left = focus.left(at: context.date)
                VStack(alignment: .leading, spacing: 6) {
                    Text(formatClock(left))
                        .font(.app(size: 30, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(focus.phase == .focus ? Theme.ink : Theme.accent2)
                        .contentTransition(.numericText())
                    SegmentMeter(value: 1 - left / max(focus.duration, 1), color: focus.phase == .focus ? Theme.accent : Theme.accent2)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                PrimaryButton(text: focus.isRunning ? "Pause" : "Start", icon: focus.isRunning ? "pause.fill" : "play.fill") {
                    focus.toggle()
                }
                IconButton(icon: "arrow.counterclockwise") { focus.reset() }.help("Reset")
                IconButton(icon: "forward.end.fill") { focus.skip() }.help("Skip")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}
