import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var focus: FocusTimer
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var lyrics: Lyrics
    @EnvironmentObject var prayer: PrayerTimes
    @EnvironmentObject var downloads: DownloadWatcher
    @EnvironmentObject var calendar: CalendarFeed
    @EnvironmentObject var countdown: CountdownTimer

    private var size: CGSize {
        model.expanded ? model.openSize : CGSize(width: model.closedWidth, height: model.closedHeight)
    }

    // Only the outline animates. The panel's content keeps its open size the whole time, so nothing is laid
    // out again frame by frame, and it stays built between openings instead of being rebuilt on each one.
    var body: some View {
        // Mini opens across the menu bar either side of the notch, so its top row is as wide as the panel.
        let neck = model.expanded ? (settings.size == .mini ? model.openSize.width : model.closedSize.width) : model.closedWidth
        let shape = NotchShape(style: settings.notchStyle, neckWidth: neck,
                              neckHeight: model.closedSize.height,
                              radius: model.expanded ? 24 : 10)
        let open = model.openSize
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                Rectangle().fill(model.expanded ? Theme.background : .black)
                // The neck stays black to blend with the hardware notch.
                Color.black.frame(height: model.closedSize.height)
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .shadow(color: .black.opacity(model.expanded ? 0.3 : 0), radius: 12, y: 6)

            ExpandedView()
                .id(settings.styleKey)
                .frame(width: open.width, height: open.height)
                // Materializes out of the notch: from blurred and squashed toward it, to sharp and full size.
                .opacity(model.expanded ? 1 : 0)
                .blur(radius: model.expanded ? 0 : 10)
                .scaleEffect(x: 1, y: model.expanded ? 1 : 0.6, anchor: .top)
                .allowsHitTesting(model.expanded)
                .mask(alignment: .top) { shape.frame(width: size.width, height: size.height) }

            closedContent
                .frame(width: model.closedWidth, height: model.closedHeight)
                .opacity(model.expanded ? 0 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(model.expanded ? .bouncy(duration: 0.4) : .smooth(duration: 0.4), value: model.expanded)
        .animation(.smooth(duration: 0.4, extraBounce: 0.1), value: model.closedWidth)
        .animation(.smooth(duration: 0.4, extraBounce: 0.1), value: model.closedHeight)
        .animation(.smooth(duration: 0.4), value: settings.size)
    }

    @ViewBuilder private var closedContent: some View {
        if let volume = model.volume {
            Ears {
                Image(systemName: volume.brightness ? (volume.level < 0.5 ? "sun.min.fill" : "sun.max.fill")
                      : volume.muted || volume.level == 0 ? "speaker.slash.fill"
                      : volume.level < 0.34 ? "speaker.wave.1.fill" : volume.level < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
                    .contentTransition(.symbolEffect(.replace))
            } right: {
                HStack(spacing: 6) {
                    Capsule().fill(.white.opacity(0.18)).frame(width: 48, height: 4)
                        .overlay(alignment: .leading) {
                            Capsule().fill(volume.muted ? Theme.dim : Theme.accent).frame(width: 48 * CGFloat(volume.level), height: 4)
                        }
                    Text(volume.muted ? "Mute" : "\(Int((volume.level * 100).rounded()))")
                        .font(.app(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                        .frame(width: 26, alignment: .trailing)
                }
                .animation(.smooth(duration: 0.2), value: volume.level)
            }
            .transition(.emerge)
        } else if let notice = model.notice {
            Ears {
                HStack(spacing: 5) {
                    Image(systemName: notice.icon).font(.system(size: 10, weight: .semibold))
                    Text(notice.left).font(.app(size: 10, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(notice.color)
            } right: {
                Text(notice.right).font(.app(size: 10, weight: .semibold)).lineLimit(1).foregroundStyle(.white)
            }
            .id(notice.id)
            .transition(.emerge)
        } else if focus.isRunning {
            Ears {
                Image(systemName: focus.phase == .focus ? "timer" : "cup.and.saucer.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(focus.phase == .focus ? Theme.accent : Theme.accent2)
            } right: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(formatClock(focus.left(at: context.date)))
                        .font(.app(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                }
            }
            .transition(.emerge)
        } else if countdown.isRunning {
            Ears {
                Image(systemName: "hourglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.accent)
            } right: {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(formatClock(countdown.left(at: context.date)))
                        .font(.app(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                }
            }
            .transition(.emerge)
        } else if let download = downloads.current {
            Ears {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 10, weight: .semibold))
                        .symbolEffect(.pulse, options: .repeating)
                    Text(download.name).font(.app(size: 10, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                }
                .foregroundStyle(Theme.accent)
            } right: {
                Text(downloads.speed > 0 ? formatRate(downloads.speed) : formatBytes(download.bytes))
                    .font(.app(size: 10, weight: .semibold)).monospacedDigit().lineLimit(1).foregroundStyle(.white)
            }
            .transition(.emerge)
        } else if let meeting = calendar.meeting {
            Ears {
                HStack(spacing: 5) {
                    Image(systemName: "video.fill").font(.system(size: 10, weight: .semibold))
                    Text(meeting.title).font(.app(size: 10.5, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(Theme.accent2)
            } right: {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let minutes = Int((meeting.start.timeIntervalSince(context.date) / 60).rounded(.up))
                    Text(minutes > 0 ? "in \(minutes) min" : "Now · join")
                        .font(.app(size: 10.5, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                }
            }
            .transition(.emerge)
        } else if model.showsPrayerCountdown, let soon = prayer.soon {
            Ears {
                HStack(spacing: 5) {
                    Image(systemName: "moon.fill").font(.system(size: 10, weight: .semibold))
                    Text(prayer.label(soon)).font(.app(size: 10.5, weight: .semibold)).lineLimit(1)
                }
                .foregroundStyle(Theme.accent)
            } right: {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    let minutes = max(1, Int((soon.time.timeIntervalSince(context.date) / 60).rounded(.up)))
                    Text("in \(minutes) min").font(.app(size: 10.5, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
                }
            }
            .transition(.emerge)
        } else if model.showsNotchLyrics {
            NotchLyrics().transition(.emerge)
        } else if model.showsMiniPlayer {
            MiniPlayer().transition(.emerge)
        }
    }
}

// Content on both sides of the camera housing, which sits in the middle of the closed notch.
private struct Ears<Left: View, Right: View>: View {
    @EnvironmentObject var model: AppModel
    @ViewBuilder var left: Left
    @ViewBuilder var right: Right

    var body: some View {
        HStack(spacing: 0) {
            left.frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: model.closedSize.width)
            right.frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: model.closedSize.height)
    }
}

// One row, the way the mini player sits: artwork and the line being sung to the left of the camera, the
// visualizer to its right. The camera housing has no pixels, so nothing crosses the middle.
private struct NotchLyrics: View {
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var lyrics: Lyrics

    var body: some View {
        Ears {
            HStack(spacing: 7) {
                Group {
                    if let art = media.artwork {
                        Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "music.note").font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 16, height: 16)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let i = media.now.flatMap { lyrics.index(at: $0.position(at: context.date)) }
                    Text(i.map { lyrics.lines[$0].text } ?? "♪")
                        .font(.app(size: 10, weight: .semibold))
                        .foregroundStyle(media.tint ?? Theme.accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(i ?? -1)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                        .animation(.easeOut(duration: 0.25), value: i)
                }
                .clipped()
            }
        } right: {
            Equalizer(playing: media.now?.playing == true, color: media.tint ?? Theme.accent)
        }
    }
}

private struct MiniPlayer: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var media: MediaController

    var body: some View {
        HStack {
            Group {
                if let art = media.artwork {
                    Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "music.note").font(.system(size: 9)).foregroundStyle(Theme.dim)
                }
            }
            .frame(width: 16, height: 16)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            Spacer()
            Equalizer(playing: true)
        }
        .padding(.horizontal, 10)
        .frame(height: model.closedSize.height)
    }
}

struct ExpandedView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: Settings

    var body: some View {
        Group {
            if settings.size == .mini { mini } else { full }
        }
        .font(.app(size: 11))
        .foregroundStyle(Theme.ink)
        .symbolRenderingMode(.monochrome)
    }

    // Mini: the tabs sit in the menu bar row either side of the notch, and the page gets everything below.
    private var mini: some View {
        let inset = 12 + (settings.notchStyle == .seamless ? NotchStyle.ear : 0)
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                EarTabs(tabs: Array(Tab.allCases.prefix(5))).frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: model.closedSize.width + 16)
                EarTabs(tabs: Array(Tab.allCases.dropFirst(5))).frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, inset)
            .frame(height: model.closedSize.height)
            .padding(.top, settings.notchStyle == .floating ? 8 : 0)
            page
                .padding(.horizontal, inset)
                .padding(.top, 6)
                .padding(.bottom, 10)
        }
    }

    private var full: some View {
        VStack(spacing: 0) {
            // The menu bar's height: the notch and the menu bar items live there.
            Color.clear.frame(height: model.closedSize.height + (settings.notchStyle == .floating ? 8 : 0))
            Group {
                if settings.layout == .classic {
                    VStack(spacing: 8) {
                        GreetingHeader()
                        page
                        DockBar()
                    }
                } else if settings.layout == .studio {
                    HStack(spacing: 12) {
                        StudioSidebar()
                        VStack(spacing: 10) {
                            Header(showsTitle: true)
                            page
                        }
                    }
                } else if settings.layout == .minimal {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            TabMenu()
                            Header(showsTitle: false)
                        }
                        page
                    }
                } else if settings.layout == .launcher {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            LauncherTitle()
                            Header(showsTitle: false)
                        }
                        if model.launcherGrid {
                            LauncherGrid().transition(.opacity.combined(with: .scale(scale: 0.98)))
                        } else {
                            page.transition(.opacity)
                        }
                    }
                    .animation(.snappy(duration: 0.25), value: model.launcherGrid)
                } else if settings.layout == .sidebar {
                    HStack(spacing: 12) {
                        Rail()
                        VStack(spacing: 10) {
                            Header(showsTitle: true)
                            page
                        }
                    }
                } else {
                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            TopTabs()
                            Header(showsTitle: false)
                        }
                        page
                    }
                }
            }
            .padding(.horizontal, 12 + (settings.notchStyle == .seamless ? NotchStyle.ear : 0))
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
    }

    // Dashboard pages scroll when the panel is shorter than them; the rest size or scroll their own content
    // (the player's artwork and the camera preview take their size from the panel, so they can't be measured).
    private var page: some View {
        Group {
            switch model.tab {
            case .home: HomeView()
            case .today: FitOrScroll { TodayView() }
            case .prayer: FitOrScroll { PrayerView() }
            case .shelf: ShelfView()
            case .clipboard: ClipboardView()
            case .music: MusicView()
            case .ai: FitOrScroll { AIView() }
            case .controls: FitOrScroll { ControlsView() }
            case .tools: ToolsView()
            case .settings: SettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }
}

private struct Header: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var calendar: CalendarFeed
    @EnvironmentObject var cleaner: Cleaner
    @EnvironmentObject var prayer: PrayerTimes
    var showsTitle: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if showsTitle {
                Text(model.tab.title).font(.app(size: 15, weight: .bold))
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)) + " · " + prayer.hijri)
                    .font(.app(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                MessagesMenu()
                KeepAwakeMenu()
                IconButton(icon: "eyedropper") { model.pickColor() }.help("Pick a color from the screen; its hex code is copied")
            }
            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            if let meeting = calendar.meeting {
                Button { calendar.join(meeting) } label: {
                    Pill(text: "Join · \(meeting.title)", color: Theme.accent2, icon: "video.fill")
                }
                .buttonStyle(PressStyle())
                .frame(maxWidth: 160)
            } else if let next = prayer.next {
                Button { model.tab = .prayer } label: {
                    Pill(text: "\(prayer.label(next)) \(next.time.formatted(date: .omitted, time: .shortened))",
                         color: Theme.accent2, icon: "moon.fill")
                }
                .buttonStyle(.plain)
            }
            if cleaner.cleaning != nil {
                Pill(text: "Cleaning \(Int(cleaner.progress * 100))%", color: Theme.accent, icon: "sparkles")
            } else if cleaner.total > 0 {
                Pill(text: "\(formatBytes(cleaner.total)) can be freed", color: Theme.amber, dot: true)
            }
        }
    }
}

// Unread chats, from Dock badges: a count, and a menu to jump into each app.
private struct MessagesMenu: View {
    @EnvironmentObject var messages: MessageBadges

    var body: some View {
        if !messages.badges.isEmpty {
            Menu {
                ForEach(messages.badges) { badge in
                    Button("\(badge.name) · \(badge.label)") { messages.open(badge) }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right.fill").font(.system(size: 9, weight: .semibold))
                    Text("\(messages.total)").font(.app(size: 10, weight: .semibold)).monospacedDigit()
                }
                .foregroundStyle(Theme.accent2)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .buttonFace(RoundedRectangle(cornerRadius: 7, style: .continuous), Theme.accent2.opacity(0.14))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Unread messages")
        }
    }
}

// Keeps the Mac awake for a while; the cup fills while it's on.
private struct KeepAwakeMenu: View {
    @EnvironmentObject var keepAwake: KeepAwake

    var body: some View {
        Menu {
            ForEach([30, 60, 120], id: \.self) { m in
                Button(m < 60 ? "Keep awake \(m) min" : "Keep awake \(m / 60) h") { keepAwake.start(minutes: m) }
            }
            Button("Keep awake until turned off") { keepAwake.start(minutes: 0) }
            if keepAwake.active {
                Divider()
                Button(keepAwake.until.map { "Turn off (on until \($0.formatted(date: .omitted, time: .shortened)))" } ?? "Turn off") {
                    keepAwake.stop()
                }
            }
        } label: {
            Image(systemName: keepAwake.active ? "mug.fill" : "mug")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(keepAwake.active ? Theme.accent : Theme.dim)
                .frame(width: 24, height: 22)
                .buttonFace(RoundedRectangle(cornerRadius: 7, style: .continuous), keepAwake.active ? Theme.accent.opacity(0.16) : Theme.ink.opacity(0.08),
                            quiet: !keepAwake.active)
        }
        // Plain, so the label keeps its own look instead of the system's menu button.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(keepAwake.active ? "Keeping the Mac awake" : "Keep the Mac awake")
    }
}

// Grouped like a dashboard's side menu: counts in mono on the right, a live mark while music plays, and the
// disk as a segmented meter at the bottom.
private struct StudioSidebar: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var shelf: Shelf
    @EnvironmentObject var clipboard: ClipboardHistory
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var prayer: PrayerTimes
    @EnvironmentObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            item(.home)
            item(.today)
            item(.prayer, count: prayer.next?.time.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
            item(.music, live: media.now?.playing == true)
            group("Files")
            item(.shelf, count: shelf.items.isEmpty ? nil : "\(shelf.items.count)")
            item(.clipboard, count: clipboard.entries.isEmpty ? nil : "\(clipboard.entries.count)")
            group("System")
            item(.ai)
            item(.controls)
            item(.tools)
            item(.settings)
            Spacer(minLength: 4)
            if settings.size == .large { DiskCard() }
        }
        .padding(5)
        .frame(width: 132)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
    }

    private func group(_ title: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.down").font(.system(size: 6.5, weight: .bold))
            Text(title.uppercased()).font(.app(size: 8, weight: .semibold)).tracking(0.8)
        }
        .foregroundStyle(Theme.faint)
        .padding(.leading, 10)
        .padding(.top, settings.size == .large ? 6 : 3)
        .padding(.bottom, 2)
    }

    private func item(_ tab: Tab, count: String? = nil, live: Bool = false) -> some View {
        let active = model.tab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) { model.tab = tab }
        } label: {
            HStack(spacing: 8) {
                TabIcon(name: tab.icon, size: 10.5).frame(width: 15)
                    .foregroundStyle(active ? Theme.ink : Theme.dim)
                Text(tab.label).font(.app(size: 11, weight: active ? .medium : .regular)).lineLimit(1)
                    .foregroundStyle(active ? Theme.ink : Theme.ink.opacity(0.75))
                Spacer(minLength: 0)
                if live {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.accent2).frame(width: 4, height: 4)
                        Text("Live").font(.app(size: 9, weight: .medium))
                    }
                    .foregroundStyle(Theme.accent2)
                } else if let count {
                    Text(count).font(.mono(size: 9)).foregroundStyle(Theme.faint)
                }
            }
            .padding(.horizontal, 8)
            // Ten rows have to fit every panel size.
            .frame(height: settings.size == .large ? 23 : settings.size == .regular ? 21 : 19)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(active ? Theme.ink.opacity(0.09) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(active ? Theme.stroke : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DiskCard: View {
    @EnvironmentObject var stats: SystemStats

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Macintosh HD").font(.app(size: 9)).foregroundStyle(Theme.dim)
                Spacer()
                Text("\(Int(stats.disk * 100))%").font(.mono(size: 9)).foregroundStyle(Theme.dim)
            }
            Text(stats.diskTotal > 0 ? "\(formatBytes(stats.diskTotal - stats.diskFree)) of \(formatBytes(stats.diskTotal))" : "—")
                .font(.app(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
            SegmentMeter(value: stats.disk, color: Theme.level(stats.disk))
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.ink.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct SegmentMeter: View {
    var value: Double
    var color: Color
    var segments = 20

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<segments, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(Double(i) < value * Double(segments) ? color : Theme.ink.opacity(0.1))
            }
        }
        .frame(height: 8)
    }
}

private struct TopTabs: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Tab.allCases) { tab in
                let active = model.tab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { model.tab = tab }
                } label: {
                    HStack(spacing: 5) {
                        TabIcon(name: tab.icon, size: 10.5, weight: .semibold)
                        if active { Text(tab.title).font(.app(size: 10, weight: .semibold)).lineLimit(1) }
                    }
                    .foregroundStyle(active ? Theme.accent : Theme.dim)
                    .padding(.horizontal, 8)
                    .frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(active ? Theme.accent.opacity(0.14) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
        .fixedSize()
    }
}

private struct Rail: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var settings: Settings

    var body: some View {
        VStack(spacing: settings.size == .compact ? 1 : 2) {
            ForEach(Tab.allCases) { tab in
                let active = model.tab == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { model.tab = tab }
                } label: {
                    TabIcon(name: tab.icon, size: 12, weight: .semibold)
                        .foregroundStyle(active ? Theme.accent : Theme.dim)
                        .frame(width: 32, height: settings.size == .compact ? 21 : 24)
                        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(active ? Theme.accent.opacity(0.14) : .clear))
                        .overlay(alignment: .leading) {
                            if active { Capsule().fill(Theme.accent).frame(width: 2.5, height: 12).offset(x: -5) }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .frame(width: 42)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
    }
}

// Minimal layout: the page's title is the menu to every other page.
private struct TabMenu: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Menu {
            ForEach(Tab.allCases) { tab in
                Button { model.tab = tab } label: { Label(tab.title, systemImage: tab.icon) }
            }
        } label: {
            HStack(spacing: 6) {
                TabIcon(name: model.tab.icon, size: 13, weight: .semibold).foregroundStyle(Theme.accent)
                Text(model.tab.title).font(.app(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.dim)
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .buttonFace(RoundedRectangle(cornerRadius: 8, style: .continuous), Theme.ink.opacity(0.06), quiet: true)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// Launcher layout: the grid's name, or a way back to the grid from a page.
private struct LauncherTitle: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if model.launcherGrid {
            Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .font(.app(size: 15, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
        } else {
            Button { model.launcherGrid = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "square.grid.3x2.fill").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .frame(width: 24, height: 22)
                        .buttonFace(RoundedRectangle(cornerRadius: 7, style: .continuous), Theme.ink.opacity(0.08))
                    Text(model.tab.title).font(.app(size: 15, weight: .bold)).foregroundStyle(Theme.ink)
                }
            }
            .buttonStyle(PressStyle())
            .help("All pages")
        }
    }
}

// Every page as a tile, with what's live on it.
private struct LauncherGrid: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var stats: SystemStats
    @EnvironmentObject var calendar: CalendarFeed
    @EnvironmentObject var prayer: PrayerTimes
    @EnvironmentObject var shelf: Shelf
    @EnvironmentObject var clipboard: ClipboardHistory
    @EnvironmentObject var media: MediaController
    @EnvironmentObject var toggles: QuickToggles

    var body: some View {
        // Two rows that share the panel's height, so the tiles fill it at every size.
        let tabs = Tab.allCases
        let rows = [Array(tabs.prefix(5)), Array(tabs.dropFirst(5))]
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: 8) {
                    ForEach(rows[r]) { tab in tile(tab) }
                }
            }
        }
    }

    private func tile(_ tab: Tab) -> some View {
        Button {
            model.tab = tab
            model.launcherGrid = false
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                TabIcon(name: tab.icon, size: 13, weight: .semibold)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.accent.opacity(0.14)))
                Spacer(minLength: 6)
                Text(tab.label).font(.app(size: 11.5, weight: .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                Text(caption(tab)).font(.app(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .buttonFace(RoundedRectangle(cornerRadius: 12, style: .continuous), Theme.surface)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private func caption(_ tab: Tab) -> String {
        switch tab {
        case .home: "CPU \(Int(stats.cpu * 100))% · \(formatMemory(stats.ramUsed))"
        case .today: calendar.items.first?.title ?? "No events ahead"
        case .prayer: prayer.next.map { "\(prayer.label($0)) \($0.time.formatted(date: .omitted, time: .shortened))" } ?? "Set your place"
        case .shelf: shelf.items.isEmpty ? "Drop files here" : "\(shelf.items.count) files"
        case .clipboard: "\(clipboard.entries.count) copied"
        case .music: media.now.map { Lyrics.clean(title: $0.title, artist: $0.artist).0 } ?? "Nothing playing"
        case .ai: "Claude Code · Codex"
        case .controls: toggles.darkMode ? "Dark mode on" : "Quick switches"
        case .tools: "Uninstall · large files"
        case .settings: "Look and behaviour"
        }
    }
}

// Icon tabs for one side of the notch in the Mini size.
private struct EarTabs: View {
    @EnvironmentObject var model: AppModel
    let tabs: [Tab]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                let active = model.tab == tab
                Button { withAnimation(.snappy(duration: 0.2)) { model.tab = tab } } label: {
                    TabIcon(name: tab.icon, size: 10.5, weight: .semibold)
                        .foregroundStyle(active ? Theme.accent : Color.white.opacity(0.55))
                        .frame(width: 26, height: 22)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(active ? Theme.accent.opacity(0.18) : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
    }
}
