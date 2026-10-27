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
                    CardHeader(title: ["Up next", "Tasks", "Month"][page],
                               subtitle: ["Calendar · next 24 hours", "End with a time for a reminder", "Dots mark days with events"][page]) {
                        Segmented(options: ["Agenda", "Tasks", "Month"], selection: $page).frame(width: 190)
                    }
                    switch page {
                    case 0: CalendarPanel()
                    case 1: TasksPanel()
                    default: MonthView()
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .card()
                TimePanel().frame(width: settings.size == .compact ? 200 : 230)
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
                     caption: prayer.place == nil ? "Set your place in Settings" : weather.failed ? "Didn't load" : "Loading…")
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

// Focus timer, a plain countdown, and other cities' clocks, one at a time.
private struct TimePanel: View {
    @State private var mode = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Segmented(options: ["Focus", "Timer", "Clocks"], selection: $mode)
            switch mode {
            case 0: FocusPage()
            case 1: TimerPage()
            default: ClocksPage()
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }
}

private struct FocusPage: View {
    @EnvironmentObject var focus: FocusTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: focus.isRunning ? 1 : 3600)) { context in
                let left = focus.left(at: context.date)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .center) {
                        Text(formatClock(left))
                            .font(.app(size: 28, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(focus.phase == .focus ? Theme.ink : Theme.accent2)
                            .contentTransition(.numericText())
                        Spacer(minLength: 4)
                        Text(focus.phase == .focus ? "Focus" : "Break").font(.app(size: 9.5, weight: .medium)).foregroundStyle(Theme.faint)
                    }
                    SegmentMeter(value: 1 - left / max(focus.duration, 1), color: focus.phase == .focus ? Theme.accent : Theme.accent2)
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                PrimaryButton(text: focus.isRunning ? "Pause" : "Start", icon: focus.isRunning ? "pause.fill" : "play.fill") {
                    focus.toggle()
                }
                // The lengths as a small menu in the button row, so the page fits short panels too.
                Menu {
                    ForEach(FocusTimer.presets.indices, id: \.self) { i in
                        let p = FocusTimer.presets[i]
                        Button("\(p.focus) min focus, \(p.rest) min break") { focus.choose(i) }
                    }
                } label: {
                    let p = FocusTimer.presets[focus.preset]
                    HStack(spacing: 3) {
                        Text("\(p.focus)/\(p.rest)").font(.mono(size: 9, weight: .semibold))
                        Image(systemName: "chevron.down").font(.system(size: 6, weight: .bold))
                    }
                    .foregroundStyle(Theme.dim)
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .buttonFace(RoundedRectangle(cornerRadius: 7, style: .continuous), Theme.ink.opacity(0.08))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                IconButton(icon: "arrow.counterclockwise") { focus.reset() }.help("Reset")
            }
        }
    }
}

private struct TimerPage: View {
    @EnvironmentObject var countdown: CountdownTimer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TimelineView(.periodic(from: .now, by: countdown.isRunning ? 1 : 3600)) { context in
                let left = countdown.left(at: context.date)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(formatClock(left)).font(.app(size: 28, weight: .bold)).monospacedDigit()
                            .contentTransition(.numericText())
                        Spacer(minLength: 4)
                        Text(countdown.isRunning ? "Running" : "Pick a time").font(.app(size: 9.5, weight: .medium)).foregroundStyle(Theme.faint)
                    }
                    SegmentMeter(value: countdown.isRunning ? 1 - left / max(countdown.duration, 1) : 0, color: Theme.accent)
                }
            }
            HStack(spacing: 2) {
                ForEach(CountdownTimer.presets, id: \.self) { m in
                    chip("\(m)m", active: countdown.isRunning && Int(countdown.duration / 60) == m) { countdown.start(minutes: m) }
                }
            }
            Spacer(minLength: 0)
            if countdown.isRunning {
                OutlineButton(text: "Cancel", color: Theme.red) { countdown.cancel() }
            } else {
                Text("Tap a time to start; it shows in the notch while it runs")
                    .font(.app(size: 8.5)).foregroundStyle(Theme.faint).lineLimit(2)
            }
        }
    }
}

private struct ClocksPage: View {
    @EnvironmentObject var clock: WorldClock

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(clock.cities, id: \.self) { city in
                            let zone = TimeZone(identifier: city.zone) ?? .current
                            HStack(spacing: 6) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(city.name).font(.app(size: 10.5, weight: .medium)).lineLimit(1)
                                    Text(Self.offset(zone, at: context.date)).font(.app(size: 8.5)).foregroundStyle(Theme.faint)
                                }
                                Spacer(minLength: 4)
                                Text(context.date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                                    .font(.app(size: 13, weight: .semibold)).monospacedDigit()
                                Button { clock.remove(city) } label: {
                                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(Theme.faint)
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(height: 28)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
            Menu {
                ForEach(WorldClock.choices.filter { !clock.cities.contains($0) }, id: \.self) { city in
                    Button(city.name) { clock.add(city) }
                }
            } label: {
                Label("Add city", systemImage: "plus").font(.app(size: 9.5, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .controlSize(.small)
            .fixedSize()
        }
    }

    // "Today, +5 h" against this Mac's time zone, or the day when it's already tomorrow there.
    private static func offset(_ zone: TimeZone, at date: Date) -> String {
        let hours = Double(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
        let text = hours == 0 ? "Same time" : (hours > 0 ? "+" : "−") + (hours.truncatingRemainder(dividingBy: 1) == 0
            ? "\(Int(abs(hours))) h" : String(format: "%.1f h", abs(hours)))
        var calendar = Calendar.current
        calendar.timeZone = zone
        let there = calendar.component(.day, from: date), here = Calendar.current.component(.day, from: date)
        return there == here ? text : (there > here || (here > 25 && there < 3) ? "Tomorrow, " : "Yesterday, ") + text
    }
}

// The month at a glance: today ringed, dots under days with events.
private struct MonthView: View {
    @EnvironmentObject var calendar: CalendarFeed
    @State private var offset = 0

    var body: some View {
        let cal = Calendar.current
        let month = cal.date(byAdding: .month, value: offset, to: Date()) ?? Date()
        let days = cal.range(of: .day, in: .month, for: month)?.count ?? 30
        let first = cal.date(from: cal.dateComponents([.year, .month], from: month)) ?? month
        let lead = (cal.component(.weekday, from: first) - cal.firstWeekday + 7) % 7
        let busy = calendar.eventDays(in: month)
        let today = offset == 0 ? cal.component(.day, from: Date()) : nil
        let symbols = Array(cal.veryShortWeekdaySymbols[(cal.firstWeekday - 1)...] + cal.veryShortWeekdaySymbols[..<(cal.firstWeekday - 1)])
        VStack(spacing: 3) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year())).font(.app(size: 10, weight: .semibold))
                Spacer()
                Button { offset -= 1 } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain)
                Button { offset = 0 } label: { Text("Today").font(.app(size: 9)) }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                Button { offset += 1 } label: { Image(systemName: "chevron.right") }.buttonStyle(.plain)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.dim)
            // One list of cells with distinct ids: weekday letters, blanks, then days (repeated ids get dropped).
            let cells = symbols.enumerated().map { ("w\($0.offset)", $0.element, 0) }
                + (0..<lead).map { ("b\($0)", "", 0) } + (1...days).map { ("d\($0)", "", $0) }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 1) {
                ForEach(cells, id: \.0) { cell in
                    if cell.2 == 0 {
                        Text(cell.1).font(.app(size: 8, weight: .semibold)).foregroundStyle(Theme.faint).frame(height: 14)
                    } else {
                        dayCell(cell.2, today: today, busy: busy)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Int, today: Int?, busy: Set<Int>) -> some View {
        Text("\(day)")
            .font(.app(size: 9, weight: day == today ? .bold : .regular)).monospacedDigit()
            .foregroundStyle(day == today ? Theme.background : Theme.ink)
            .frame(width: 18, height: 14)
            .background(Capsule().fill(day == today ? Theme.accent : .clear))
            .overlay(alignment: .bottom) {
                if busy.contains(day), day != today { Circle().fill(Theme.accent2).frame(width: 3, height: 3).offset(y: 2) }
            }
    }
}

private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
        Text(text)
            .font(.mono(size: 8.5, weight: .semibold))
            .foregroundStyle(active ? Theme.ink : Theme.faint)
            .padding(.horizontal, 5)
            .frame(height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(active ? Theme.ink.opacity(0.1) : .clear))
            .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
}
