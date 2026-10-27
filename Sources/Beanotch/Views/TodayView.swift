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
                    CardHeader(title: ["Up next", "Tasks", "Month", "Rates"][page],
                               subtitle: ["Calendar · next 24 hours", "End with a time for a reminder", "Dots mark days with events",
                                          "In \(Rates.local)"][page]) {
                        Segmented(options: ["Agenda", "Tasks", "Month", "Rates"], selection: $page).fixedSize()
                    }
                    switch page {
                    case 0: CalendarPanel()
                    case 1: TasksPanel()
                    case 2: MonthView()
                    default: RatesPanel()
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

// Exchange rates and gold, in the local currency, three to a row.
private struct RatesPanel: View {
    @EnvironmentObject var rates: Rates

    var body: some View {
        Group {
            if rates.perDollar.isEmpty {
                LoadingView(text: "Getting today's rates…")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                    ForEach(Rates.watched, id: \.self) { code in
                        cell(code, value: rates.value(of: code), change: rates.change(code, now: rates.value(of: code)))
                    }
                    cell("Gold", value: rates.goldGram, change: rates.change("gold", now: rates.goldGram), unit: " / g")
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { await rates.refresh() }
    }

    private func cell(_ code: String, value: Double?, change: Double?, unit: String = "") -> some View {
        let tint = code == "Gold" ? Theme.amber : Theme.accent
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(code + unit).font(.app(size: 8.5, weight: .bold)).foregroundStyle(tint)
                Spacer(minLength: 2)
                if let change {
                    Text((change >= 0 ? "▲" : "▼") + abs(change * 100).formatted(.number.precision(.fractionLength(1))) + "%")
                        .font(.app(size: 8, weight: .semibold)).foregroundStyle(change >= 0 ? Theme.good : Theme.red)
                }
            }
            Text(value.map { Rates.format($0, Rates.local) } ?? "–")
                .font(.app(size: 11.5, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 40)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.opacity(0.06)))
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

// The ring on the left fills as the stretch runs, with play/pause in its middle; beside it the time, the phase and
// when it ends, then the lengths and a jump between focus and a break. Focus burns orange to red, the break cools to blue.
private struct FocusPage: View {
    @EnvironmentObject var focus: FocusTimer
    @EnvironmentObject var settings: Settings

    private var resting: Bool { focus.phase == .rest }

    private var colors: [Color] {
        resting ? [Color(red: 0.3, green: 0.62, blue: 1), Color(red: 0.12, green: 0.4, blue: 0.86)]
                : [Color(red: 1, green: 0.5, blue: 0.16), Color(red: 0.9, green: 0.27, blue: 0.16)]
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: focus.isRunning ? 1 : 3600)) { context in
            let left = focus.left(at: context.date)
            let progress = min(1, max(0.002, 1 - left / max(focus.duration, 1)))
            HStack(spacing: 12) {
                TimerRing(progress: progress, colors: colors, icon: focus.isRunning ? "pause.fill" : "play.fill",
                          help: focus.isRunning ? "Pause" : "Start") { focus.toggle() }

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatClock(left))
                        .font(.app(size: 30, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    HStack(spacing: 5) {
                        Circle().fill(colors[0]).frame(width: 6, height: 6)
                        Text(status(left: left, at: context.date))
                            .font(.app(size: 9.5, weight: .medium)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    controls
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    private func status(left: TimeInterval, at date: Date) -> String {
        let phase = resting ? "Break" : "Focus"
        guard focus.isRunning else { return "\(phase) · \(left < focus.duration ? "paused" : "\(Int(focus.duration / 60)) min")" }
        return "\(phase) · ends " + date.addingTimeInterval(left).formatted(date: .omitted, time: .shortened)
    }

    private var controls: some View {
        HStack(spacing: 6) {
            // The lengths and a reset behind the gear, so the page fits short panels too.
            Menu {
                ForEach(FocusTimer.presets.indices, id: \.self) { i in
                    let p = FocusTimer.presets[i]
                    Button("\(p.focus) min focus, \(p.rest) min break\(i == focus.preset ? "  ✓" : "")") { focus.choose(i) }
                }
                Divider()
                Menu("Sound while focusing") {
                    Button("None\(settings.focusSound.isEmpty ? "  ✓" : "")") { settings.focusSound = "" }
                    ForEach(Ambient.Sound.allCases) { sound in
                        Button("\(sound.title)\(settings.focusSound == sound.rawValue ? "  ✓" : "")") { settings.focusSound = sound.rawValue }
                    }
                }
                Divider()
                Button("Reset") { focus.reset() }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().strokeBorder(Theme.ink.opacity(0.18)))
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Lengths and reset")
            Button { focus.skip() } label: {
                Text(resting ? "Focus" : "Break")
                    .font(.app(size: 9.5, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 24)
                    .background(Capsule().fill(Theme.ink.opacity(0.1)))
                    .contentShape(Capsule())
            }
            .buttonStyle(PressStyle())
            .help(resting ? "Back to focus" : "Take a break now")
        }
    }
}

// The ring and the time beside it, as in Focus. The ring empties as the countdown runs; the menu picks the length.
private struct TimerPage: View {
    @EnvironmentObject var countdown: CountdownTimer

    private let colors = [Color(red: 0.25, green: 0.8, blue: 0.9), Color(red: 0.3, green: 0.55, blue: 1)]

    var body: some View {
        TimelineView(.periodic(from: .now, by: countdown.isRunning ? 1 : 3600)) { context in
            let left = countdown.left(at: context.date)
            let progress = countdown.isRunning ? min(1, max(0.002, left / max(countdown.duration, 1))) : 1
            HStack(spacing: 12) {
                TimerRing(progress: progress, colors: colors, icon: countdown.isRunning ? "stop.fill" : "play.fill",
                          help: countdown.isRunning ? "Stop" : "Start") {
                    countdown.isRunning ? countdown.cancel() : countdown.start(minutes: Int(countdown.duration / 60))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatClock(left))
                        .font(.app(size: 30, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    HStack(spacing: 5) {
                        Circle().fill(colors[0]).frame(width: 6, height: 6)
                        Text(countdown.isRunning ? "Ends " + context.date.addingTimeInterval(left).formatted(date: .omitted, time: .shortened)
                                                 : "Shows in the notch")
                            .font(.app(size: 9.5, weight: .medium)).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    lengths
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
    }

    // Picking a length while the timer runs starts it over at that length.
    private var lengths: some View {
        Menu {
            ForEach(CountdownTimer.presets, id: \.self) { m in
                Button("\(m) min\(Int(countdown.duration / 60) == m ? "  ✓" : "")") {
                    countdown.isRunning ? countdown.start(minutes: m) : countdown.choose(minutes: m)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(Int(countdown.duration / 60)) min").font(.app(size: 9.5, weight: .semibold))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(Capsule().fill(Theme.ink.opacity(0.1)))
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Length")
    }
}

// A ring of progress with one round button in its middle, for Focus and Timer.
private struct TimerRing: View {
    let progress: Double
    let colors: [Color]
    let icon: String
    let help: String
    let action: () -> Void

    var body: some View {
        ZStack {
            Circle().stroke(Theme.ink.opacity(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: colors, center: .center, startAngle: .zero, endAngle: .degrees(360 * progress)),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: progress)
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.ink.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(PressStyle())
            .help(help)
        }
        .padding(3)
        .aspectRatio(1, contentMode: .fit)
        .frame(maxHeight: .infinity)
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

