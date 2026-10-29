import SwiftUI

// Glance: one page and no menu. A card each for what's playing, what's coming up and the focus timer, read at a look,
// with the Shelf's count and the way to Settings under them.
struct GlanceView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var shelf: Shelf

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                NowCard()
                NextCard()
                FocusCard().frame(width: 132)
            }
            HStack(spacing: 6) {
                if !shelf.items.isEmpty {
                    Label("\(shelf.items.count) on the Shelf", systemImage: "tray.full.fill")
                        .font(.app(size: 9, weight: .medium)).foregroundStyle(Theme.faint)
                }
                Spacer()
                Button { model.openSettings(nil) } label: {
                    Image(systemName: "gearshape.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.faint)
                        .frame(width: 18, height: 14).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Settings and tools")
            }
            .frame(height: 14)
        }
    }
}

// What's playing: the cover, the song, a thin progress line and the three controls.
private struct NowCard: View {
    @EnvironmentObject var media: MediaController

    var body: some View {
        Group {
            if let now = media.now {
                let tint = media.tint ?? Theme.accent
                let shown = Lyrics.clean(title: now.title, artist: now.artist)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 9) {
                        Group {
                            if let art = media.artwork {
                                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                            } else {
                                ZStack { Theme.ink.opacity(0.08); Image(systemName: "music.note").foregroundStyle(Theme.dim) }
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shown.0.isEmpty ? now.title : shown.0).font(.app(size: 12, weight: .bold)).lineLimit(1)
                            Text(shown.1.isEmpty ? now.app : shown.1).font(.app(size: 10)).foregroundStyle(Theme.dim).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                    TimelineView(.periodic(from: .now, by: now.playing ? 1 : 3600)) { context in
                        ProgressTrack(value: now.duration > 0 ? now.position(at: context.date) / now.duration : 0, color: tint) {
                            media.seek($0 * now.duration)
                        }
                    }
                    HStack(spacing: 8) {
                        control("backward.end.fill") { media.previous() }
                        Button { media.playPause() } label: {
                            Image(systemName: now.playing ? "pause.fill" : "play.fill").font(.system(size: 11, weight: .bold)).foregroundStyle(.black)
                                .frame(width: 30, height: 30).buttonFace(Circle(), tint).contentShape(Circle())
                        }
                        .buttonStyle(PressStyle())
                        control("forward.end.fill") { media.next() }
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note").font(.system(size: 18, weight: .light)).foregroundStyle(Theme.faint)
                    Text("Nothing playing").font(.app(size: 11, weight: .semibold)).foregroundStyle(Theme.dim)
                    Text("Play something in any app").font(.app(size: 9)).foregroundStyle(Theme.faint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
    }

    private func control(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 9, weight: .bold))
                .frame(width: 24, height: 24).buttonFace(Circle(), Theme.ink.opacity(0.09)).contentShape(Circle())
        }
        .buttonStyle(PressStyle())
    }
}

// What's coming up: the next events and the next prayer, in time order; with nothing ahead, the weather.
private struct NextCard: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var calendar: CalendarFeed
    @EnvironmentObject var prayer: PrayerTimes
    @EnvironmentObject var weather: Weather

    private struct Row: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let time: Date
        let title: String
    }

    private var rows: [Row] {
        var rows = calendar.items.filter { $0.end > Date() }.prefix(3)
            .map { Row(id: $0.id, icon: "circle.fill", color: $0.color, time: $0.start, title: $0.title) }
        if model.prayerOn, let next = prayer.next {
            rows.append(Row(id: "prayer", icon: "moon.fill", color: Theme.accent2, time: next.time, title: prayer.label(next)))
        }
        return Array(rows.sorted { $0.time < $1.time }.prefix(3))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text("Up next").font(.app(size: 11, weight: .bold))
                Spacer()
                Text(Date().formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                    .font(.app(size: 9, weight: .medium)).foregroundStyle(Theme.faint)
            }
            if rows.isEmpty {
                Spacer(minLength: 0)
                if let report = weather.report {
                    HStack(spacing: 8) {
                        Image(systemName: Weather.symbol(report.code)).symbolRenderingMode(.hierarchical).font(.system(size: 20))
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(Int(report.temp.rounded()))°").font(.app(size: 16, weight: .bold))
                            Text(Weather.describe(report.code)).font(.app(size: 9)).foregroundStyle(Theme.dim).lineLimit(1)
                        }
                    }
                }
                Text("Nothing on the calendar").font(.app(size: 9.5)).foregroundStyle(Theme.faint)
                Spacer(minLength: 0)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 7) {
                        Image(systemName: row.icon).font(.system(size: row.icon == "circle.fill" ? 5 : 8)).foregroundStyle(row.color).frame(width: 9)
                        Text(row.time.formatted(date: .omitted, time: .shortened)).font(.mono(size: 9.5)).foregroundStyle(Theme.dim)
                        Text(row.title).font(.app(size: 10.5, weight: .medium)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card()
        .task { weather.refresh(for: prayer.place) }
    }
}

// The focus timer: its ring with play and pause in the middle, and the time left under it.
private struct FocusCard: View {
    @EnvironmentObject var focus: FocusTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: focus.isRunning ? 1 : 3600)) { context in
            let left = focus.left(at: context.date)
            let resting = focus.phase == .rest
            let colors = resting ? [Color(red: 0.3, green: 0.62, blue: 1), Color(red: 0.12, green: 0.4, blue: 0.86)]
                                 : [Color(red: 1, green: 0.5, blue: 0.16), Color(red: 0.9, green: 0.27, blue: 0.16)]
            VStack(spacing: 4) {
                TimerRing(progress: min(1, max(0.002, 1 - left / max(focus.duration, 1))), colors: colors,
                          icon: focus.isRunning ? "pause.fill" : "play.fill", help: focus.isRunning ? "Pause" : "Start") { focus.toggle() }
                Text(formatClock(left)).font(.app(size: 15, weight: .bold)).monospacedDigit()
                Text(resting ? "Break" : "Focus").font(.app(size: 9)).foregroundStyle(Theme.dim)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .card()
        }
    }
}

// Bar: one slim row and no menu. The song and its controls, the focus timer, and what's coming up, side by side.
struct BarView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var focus: FocusTimer
    @EnvironmentObject var calendar: CalendarFeed
    @EnvironmentObject var prayer: PrayerTimes

    var body: some View {
        HStack(spacing: 12) {
            song.frame(maxWidth: .infinity, alignment: .leading)
            divider
            timer
            divider
            next.frame(maxWidth: 120, alignment: .leading)
            Button { model.openSettings(nil) } label: {
                Image(systemName: "gearshape.fill").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.faint)
                    .frame(width: 16, height: 16).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings and tools")
        }
        .padding(.horizontal, 4)
        .frame(maxHeight: .infinity)
    }

    private var divider: some View { Rectangle().fill(Theme.stroke).frame(width: 1, height: 30) }

    private var song: some View {
        HStack(spacing: 9) {
            Group {
                if let art = media.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack { Theme.ink.opacity(0.08); Image(systemName: "music.note").font(.system(size: 11)).foregroundStyle(Theme.dim) }
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            // The song's name gets the room first; the rest of the row keeps to its size.
            VStack(alignment: .leading, spacing: 1) {
                let shown = media.now.map { Lyrics.clean(title: $0.title, artist: $0.artist) }
                Text(shown.map { $0.0.isEmpty ? media.now?.title ?? "" : $0.0 } ?? "Nothing playing")
                    .font(.app(size: 11.5, weight: .bold)).lineLimit(1)
                Text(shown.map { $0.1.isEmpty ? media.now?.app ?? "" : $0.1 } ?? "Play something in any app")
                    .font(.app(size: 9.5)).foregroundStyle(Theme.dim).lineLimit(1)
            }
            .frame(minWidth: 70, alignment: .leading)
            .layoutPriority(1)
            Spacer(minLength: 0)
            if let now = media.now {
                HStack(spacing: 5) {
                    Button { media.playPause() } label: {
                        Image(systemName: now.playing ? "pause.fill" : "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.black)
                            .frame(width: 28, height: 28).buttonFace(Circle(), media.tint ?? Theme.accent).contentShape(Circle())
                    }
                    .buttonStyle(PressStyle())
                    small("forward.end.fill") { media.next() }
                }
            }
        }
    }

    private var timer: some View {
        TimelineView(.periodic(from: .now, by: focus.isRunning ? 1 : 3600)) { context in
            HStack(spacing: 8) {
                Button { focus.toggle() } label: {
                    Image(systemName: focus.isRunning ? "pause.fill" : "timer").font(.system(size: 10, weight: .bold))
                        .frame(width: 28, height: 28).buttonFace(Circle(), Theme.ink.opacity(0.09)).contentShape(Circle())
                }
                .buttonStyle(PressStyle())
                .help(focus.isRunning ? "Pause" : "Start focus")
                VStack(alignment: .leading, spacing: 0) {
                    Text(formatClock(focus.left(at: context.date))).font(.app(size: 13, weight: .bold)).monospacedDigit()
                    Text(focus.phase == .rest ? "Break" : "Focus").font(.app(size: 9)).foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var next: some View {
        let event = model.nextEvent
        let prayerNext = model.prayerOn ? prayer.next : nil
        // Whichever comes first: the next event or the next prayer.
        let useEvent = event.map { e in prayerNext.map { e.start <= $0.time } ?? true } ?? false
        return HStack(spacing: 7) {
            Image(systemName: useEvent ? "calendar" : prayerNext != nil ? "moon.fill" : "sun.max.fill")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent2)
            VStack(alignment: .leading, spacing: 0) {
                if useEvent, let event {
                    Text(event.title).font(.app(size: 10.5, weight: .semibold)).lineLimit(1)
                    Text(event.start.formatted(date: .omitted, time: .shortened)).font(.app(size: 9)).foregroundStyle(Theme.dim)
                } else if let p = prayerNext {
                    Text(prayer.label(p)).font(.app(size: 10.5, weight: .semibold)).lineLimit(1)
                    Text(p.time.formatted(date: .omitted, time: .shortened)).font(.app(size: 9)).foregroundStyle(Theme.dim)
                } else {
                    Text(Date().formatted(.dateTime.weekday(.wide))).font(.app(size: 10.5, weight: .semibold)).lineLimit(1)
                    Text(Date().formatted(.dateTime.day().month(.abbreviated))).font(.app(size: 9)).foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private func small(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 8.5, weight: .bold))
                .frame(width: 22, height: 22).buttonFace(Circle(), Theme.ink.opacity(0.09)).contentShape(Circle())
        }
        .buttonStyle(PressStyle())
    }
}
