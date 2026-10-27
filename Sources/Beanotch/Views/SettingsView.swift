import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var clipboard: ClipboardHistory
    @EnvironmentObject var prayer: PrayerTimes
    @EnvironmentObject var updater: Updater
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var messages: MessageBadges
    @EnvironmentObject var devRuns: DevRuns
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private static let delays: [Double] = [0.6, 1.2, 2.5]
    private static let reminders = [0, 5, 10, 15]
    private static let waterSteps = [0, 30, 60, 90]
    private static let stretchSteps = [0, 45, 60, 90]

    @State private var section: Section = .appearance

    enum Section: String, CaseIterable, Identifiable {
        case appearance, pages, notch, inNotch, ai, shelf, wellbeing, prayer, system
        var id: String { rawValue }
        var title: String {
            switch self {
            case .appearance: "Appearance"
            case .pages: "Pages"
            case .ai: "AI"
            case .notch: "Notch"
            case .inNotch: "In the notch"
            case .shelf: "Files"
            case .wellbeing: "Wellbeing"
            case .prayer: "Prayer times"
            case .system: "System"
            }
        }
        var icon: String {
            switch self {
            case .appearance: "paintbrush.fill"
            case .pages: "square.stack.fill"
            case .ai: "sparkles"
            case .notch: "rectangle.topthird.inset.filled"
            case .inNotch: "bell.badge.fill"
            case .shelf: "tray.full.fill"
            case .wellbeing: "heart.fill"
            case .prayer: "moon.fill"
            case .system: "gearshape.fill"
            }
        }
    }

    // Sections down the side, one at a time on the right, so nothing is a long scroll.
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Section.allCases) { item in sectionButton(item) }
                    }
                }
                .scrollIndicators(.never)
                .scrollBounceBehavior(.basedOnSize)
                HStack(spacing: 6) {
                    Text("Beanotch \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                        .font(.mono(size: 8.5)).foregroundStyle(Theme.faint).lineLimit(1)
                    Spacer(minLength: 0)
                    Button { NSApp.terminate(nil) } label: {
                        Image(systemName: "power").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.red)
                            .frame(width: 20, height: 18).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle())
                    .help("Quit Beanotch")
                }
                .padding(.leading, 8)
                .padding(.top, 4)
                .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
            }
            .frame(width: 124)
            .frame(maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .trailing) { Rectangle().fill(Theme.stroke).frame(width: 1).offset(x: 6) }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    content
                }
                .padding(.bottom, 2)
            }
            .scrollIndicators(.never)
            .id(section)
        }
    }

    private func sectionButton(_ item: Section) -> some View {
        let active = section == item
        // Without the Prayer page, its section only keeps the place, for the weather.
        let plain = item == .prayer && !model.prayerOn
        return Button { withAnimation(.snappy(duration: 0.2)) { section = item } } label: {
            HStack(spacing: 7) {
                TabIcon(name: plain ? "location.fill" : item.icon, size: 10, weight: .semibold).frame(width: 14)
                    .foregroundStyle(active ? Theme.accent : Theme.dim)
                Text(plain ? "Location" : item.title).font(.app(size: 10.5, weight: active ? .semibold : .regular)).lineLimit(1)
                    .foregroundStyle(active ? Theme.ink : Theme.ink.opacity(0.75))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: settings.size == .mini ? 18 : 21)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(active ? Theme.ink.opacity(0.08) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .appearance: appearance
        case .pages: pages
        case .ai: aiSection
        case .notch: notch
        case .inNotch: inNotch
        case .shelf: shelfSection
        case .wellbeing: wellbeing
        case .prayer: prayerSection
        case .system: system
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 8) {
            card {
                pickerRow("Theme", "The notch itself always stays black") {
                    HStack(spacing: 6) {
                        ForEach(ThemeMode.allCases, id: \.self) { mode in
                            choice(mode.title, selected: settings.theme == mode) { settings.theme = mode } preview: { ThemeSwatch(mode: mode) }
                        }
                    }
                }
                pickerRow("Accent", "Buttons, highlights and the mini player") {
                    HStack(spacing: 4) {
                        ForEach(AccentChoice.allCases, id: \.self) { option in
                            Button { settings.accent = option } label: {
                                Circle().fill(option.primary).frame(width: 14, height: 14)
                                    .overlay(Circle().strokeBorder(Theme.background, lineWidth: settings.accent == option ? 2 : 0))
                                    .overlay(Circle().strokeBorder(option.primary, lineWidth: settings.accent == option ? 1 : 0).padding(-2))
                                    .padding(4)
                                    .contentShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .help(option.rawValue.capitalized)
                        }
                    }
                }
            }
            card {
                pickerRow("Layout", settings.size == .mini ? "Mini keeps the tabs beside the notch; pick Compact or bigger to use a layout"
                                                           : settings.layout.caption) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                        ForEach(LayoutStyle.allCases, id: \.self) { layout in
                            choice(layout.title, selected: settings.layout == layout && settings.size != .mini) {
                                settings.layout = layout
                                // Picking a layout while Mini is on moves up to a size that has one.
                                if settings.size == .mini { settings.size = .compact }
                            } preview: { LayoutSketch(layout: layout) }
                        }
                    }
                }
                pickerRow("Notch shape", "How the panel opens out of the notch") {
                    HStack(spacing: 6) {
                        ForEach(NotchStyle.allCases, id: \.self) { style in
                            choice(style.title, selected: settings.notchStyle == style) { settings.notchStyle = style } preview: { ShapeSketch(style: style) }
                        }
                    }
                }
            }
            card {
                row("arrow.up.left.and.arrow.down.right", "Panel size", "How big the panel opens") {
                    Segmented(options: PanelSize.allCases.map(\.title), selection: index($settings.size, PanelSize.allCases))
                }
                pickerRow("Font", "SF Pro matches the icons; the others ship with Beanotch") {
                    Segmented(options: AppFont.allCases.map(\.title), selection: index($settings.font, AppFont.allCases))
                }
            }
        }
    }

    // Pages to keep in the menus; the rest disappear from every layout.
    private var pages: some View {
        card {
            ForEach(Tab.allCases.filter { $0 != .settings }) { tab in
                row(tab.icon, tab.title, caption(for: tab)) {
                    Toggle("", isOn: Binding(
                        get: { !settings.hiddenTabs.contains(tab.rawValue) },
                        set: { on in
                            if on { settings.hiddenTabs.remove(tab.rawValue) } else { settings.hiddenTabs.insert(tab.rawValue) }
                        }))
                }
            }
        }
    }

    private func caption(for tab: Tab) -> String {
        switch tab {
        case .prayer: "Off also hides prayer times in the header and the notch, and the Hijri date"
        case .home: "System stats and cleanup"
        case .today: "Weather, calendar, tasks and timers"
        case .music: "The player and lyrics; the notch still shows what's playing"
        case .shelf: "Files dropped on the notch still land here"
        case .clipboard: "History and notes"
        case .ai: "Claude Code and Codex usage"
        case .controls: "Quick switches, brightness, batteries, Shortcuts"
        case .tools: "Uninstaller, large files, camera mirror"
        case .settings: ""
        }
    }

    private var aiSection: some View {
        card {
            row("cpu", "Model", "Used by Ask, clipboard actions and screenshot names") {
                Menu {
                    ForEach(Assistant.Engine.allCases) { option in
                        Button(option.title + (Assistant.available(option) ? "" : " (not found)")) { settings.aiEngine = option.rawValue }
                            .disabled(!Assistant.available(option))
                    }
                } label: {
                    Text((Assistant.Engine(rawValue: settings.aiEngine) ?? .onDevice).title).font(.app(size: 10, weight: .semibold))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            row("asterisk", "Claude Code in the notch",
                settings.claudeBridge ? "Status and permission requests show in the notch · hooks added to ~/.claude/settings.json"
                                      : "Adds hooks to ~/.claude/settings.json; switching off removes them") {
                Toggle("", isOn: $settings.claudeBridge)
            }
            row("terminal", "Terminal commands",
                devRuns.installedAt.map { "Run `beanotch run npm test` to follow it in the notch · in \($0)" }
                    ?? "Adds a `beanotch` command: long builds and tests show in the notch, green or red when done") {
                if devRuns.installedAt == nil {
                    PillButton(text: "Install", color: Theme.accent) { devRuns.install() }
                } else {
                    PillButton(text: "Remove", color: Theme.dim) { devRuns.uninstall() }
                }
            }
            row("camera.viewfinder", "Name screenshots", "Renames new screenshots after what they show, before they reach the Shelf") {
                Toggle("", isOn: $settings.nameScreenshots)
            }
        }
    }

    private var notch: some View {
        card {
            row("cursorarrow.motionlines", "Open on hover", "Off: click the notch or press the shortcut") {
                Toggle("", isOn: $settings.openOnHover)
            }
            row("timer", "Close after leaving", "How long the panel waits for the pointer to come back") {
                Segmented(options: ["Fast", "Normal", "Relaxed"], selection: index($settings.closeDelay, Self.delays))
            }
            row("command", "Shortcut", "Open and close the panel from anywhere; click to change it") {
                HStack(spacing: 8) {
                    ShortcutRecorder()
                    Toggle("", isOn: $settings.hotkey)
                }
            }
            row("hand.draw", "Gestures", "Over the notch: swipe sideways to change song, scroll for volume") {
                Toggle("", isOn: $settings.gestures)
            }
            row("arrow.up.left.and.arrow.down.right.rectangle", "Hide in full screen", "Out of the way during videos and presentations") {
                Toggle("", isOn: $settings.hideInFullScreen)
            }
        }
    }

    private var inNotch: some View {
        VStack(alignment: .leading, spacing: 8) {
            card {
                row("bubble.left.and.bubble.right", "Messages",
                    messages.trusted ? "Unread counts from Dock badges: WhatsApp, Telegram, Slack, Mail…"
                        : "Needs Accessibility access to read Dock badges") {
                    HStack(spacing: 8) {
                        if !messages.trusted {
                            PillButton(text: "Allow", color: Theme.accent) {
                                messages.requestAccess()
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                            }
                        }
                        Toggle("", isOn: $settings.messageAlerts)
                    }
                }
                row("app.badge", "Badges from every app", "Not only chat apps, any app showing a Dock badge") {
                    Toggle("", isOn: $settings.messageAllApps)
                }
                row("bell.badge", "Notch alerts", "Charging, low battery, headphones, screenshots") {
                    Toggle("", isOn: $settings.notchAlerts)
                }
                row("speaker.wave.2", "Volume & brightness", "The level shows in the notch when it changes") {
                    Toggle("", isOn: $settings.volumeHUD)
                }
                row("arrow.down.circle", "Downloads", "Progress of browser downloads, and when they finish") {
                    Toggle("", isOn: $settings.downloadsInNotch)
                }
                row("capslock", "Keyboard", "Caps Lock and keyboard language changes") {
                    Toggle("", isOn: $settings.keyboardAlerts)
                }
                row("video", "Calls", "While the mic or camera is on: call time and mute in the notch, other alerts wait") {
                    Toggle("", isOn: $settings.meetingMode)
                }
            }
            card {
                row("music.note", "Mini player", "Artwork and bars beside the notch while music plays") {
                    Toggle("", isOn: $settings.miniPlayer)
                }
                row("music.note.list", "Song changes", "The new song's title shows for a moment") {
                    Toggle("", isOn: $settings.songFlash)
                }
                row("text.quote", "Lyrics in the notch", "The line being sung, beside the notch, while it's closed") {
                    Toggle("", isOn: $settings.lyricsInNotch)
                }
                row("quote.bubble", "Lyrics", "LRCLIB, NetEase, QQ Music and Kugou: title and artist are sent to look them up") {
                    Toggle("", isOn: $settings.lyrics)
                }
            }
        }
    }

    private var shelfSection: some View {
        card {
            row("camera.viewfinder", "Screenshots to Shelf", "New screenshots land on the Shelf, ready to drag") {
                Toggle("", isOn: $settings.screenshotsToShelf)
            }
            row("doc.on.clipboard", "Clipboard history", "Keeps the last 100 texts and images you copy") {
                Toggle("", isOn: $clipboard.enabled)
            }
        }
    }

    private var wellbeing: some View {
        card {
            row("drop", "Drink water", "Minutes between reminders, 8:00 to 22:00") {
                Segmented(options: ["Off", "30", "60", "90"], selection: index($settings.waterEvery, Self.waterSteps))
            }
            row("eye", "Eye breaks", "Every 20 minutes, look 6 m away for 20 seconds") {
                Toggle("", isOn: $settings.eyeBreaks)
            }
            row("figure.walk", "Stand up", "Minutes between stretch reminders") {
                Segmented(options: ["Off", "45", "60", "90"], selection: index($settings.stretchEvery, Self.stretchSteps))
            }
        }
    }

    private var prayerSection: some View {
        card {
            row("location", "Location", (prayer.place?.name ?? "Not set") + (model.prayerOn ? "" : " · used for the weather")) {
                CityMenu(label: "Change")
            }
            if model.prayerOn {
                row("function", "Method", "Fajr and Isha angles") {
                    Menu {
                        ForEach(PrayerTimes.Method.allCases) { m in Button(m.title) { prayer.method = m } }
                    } label: {
                        Text(prayer.method.title).font(.app(size: 10, weight: .semibold))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                row("sun.haze", "Asr", "Hanafi waits for a shadow twice an object's length") {
                    Segmented(options: ["Standard", "Hanafi"], selection: Binding(get: { prayer.hanafi ? 1 : 0 },
                                                                               set: { prayer.hanafi = $0 == 1 }))
                }
                row("moon", "Prayer alerts", "A notice and a sound in the notch at each prayer") {
                    Toggle("", isOn: $prayer.alerts)
                }
                row("hourglass", "Countdown in the notch", "Before each prayer, and Imsak and iftar in Ramadan") {
                    Toggle("", isOn: $settings.prayerCountdown)
                }
                row("alarm", "Remind me before", "Minutes before each prayer") {
                    Segmented(options: ["Off", "5", "10", "15"], selection: index($prayer.reminder, Self.reminders))
                }
            }
        }
    }

    private var system: some View {
        card {
            row("power", "Open at login", loginError ?? "Start Beanotch when you log in") {
                Toggle("", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
            }
            row("arrow.down.app", "Updates", updateCaption) {
                HStack(spacing: 8) {
                    if updater.updateAvailable {
                        PillButton(text: updater.installing ? "Installing…" : "Install \(updater.latest ?? "")", color: Theme.accent) { updater.install() }
                    } else {
                        PillButton(text: updater.checking ? "Checking…" : "Check now", color: Theme.accent2) { updater.check() }
                    }
                    Toggle("", isOn: $updater.automatic).help("Check once a day")
                }
            }
            row("lock.shield", "Full Disk Access", "Needed to clean Safari's cache") {
                PillButton(text: "Open Settings", color: Theme.accent2) {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                }
            }
        }
    }

    // A title over a row of visual choices.
    private func pickerRow(_ title: String, _ caption: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title).font(.app(size: 11, weight: .medium))
                Text(caption).font(.app(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            content()
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private func choice(_ title: String, selected: Bool, action: @escaping () -> Void,
                        @ViewBuilder preview: () -> some View) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                preview()
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(selected ? Theme.accent : Theme.stroke, lineWidth: selected ? 1.5 : 1))
                Text(title).font(.app(size: 9.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.ink : Theme.dim).lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle())
    }

    private func index<T: Equatable>(_ value: Binding<T>, _ all: [T]) -> Binding<Int> {
        Binding(get: { all.firstIndex(of: value.wrappedValue) ?? 0 }, set: { value.wrappedValue = all[$0] })
    }

    private var updateCaption: String {
        if let error = updater.installError { return error }
        if updater.failed { return "Couldn't reach GitHub" }
        if updater.updateAvailable { return "Beanotch \(updater.latest ?? "") is out, you have \(updater.current)" }
        if updater.latest != nil { return "Up to date (\(updater.current))" }
        return "Looks for a new release on GitHub once a day"
    }

    private func card(@ViewBuilder _ rows: () -> some View) -> some View {
        VStack(spacing: 0) { rows() }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ icon: String, _ title: String, _ caption: String,
                     @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 11, weight: .medium)).frame(width: 18).foregroundStyle(Theme.dim)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.app(size: 11, weight: .medium))
                Text(caption).font(.app(size: 9)).foregroundStyle(Theme.faint).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing().toggleStyle(AccentSwitchStyle()).labelsHidden()
        }
        .padding(.horizontal, 11)
        .frame(height: 34)
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Move Beanotch to Applications first"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

// A tiny panel in each theme: light, dark, half-and-half, true black, or frosted.
private struct ThemeSwatch: View {
    let mode: ThemeMode

    var body: some View {
        let dark = Color(red: 0.07, green: 0.07, blue: 0.08), light = Color(red: 0.95, green: 0.95, blue: 0.94)
        GeometryReader { geo in
            ZStack {
                switch mode {
                case .dark: dark
                case .light: light
                case .midnight: Color.black
                case .glass:
                    LinearGradient(colors: [Color(red: 0.45, green: 0.55, blue: 0.85), Color(red: 0.75, green: 0.5, blue: 0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(Color.black.opacity(0.15))
                default: HStack(spacing: 0) { light; dark }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Capsule().fill(Theme.accent).frame(width: geo.size.width * 0.35, height: 4)
                    Capsule().fill(Color.gray.opacity(0.5)).frame(width: geo.size.width * 0.55, height: 3)
                    Capsule().fill(Color.gray.opacity(0.35)).frame(width: geo.size.width * 0.45, height: 3)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(7)
            }
        }
    }
}

// A wireframe of each layout, drawn with blocks.
private struct LayoutSketch: View {
    let layout: LayoutStyle

    var body: some View {
        let block = Theme.ink.opacity(0.13), accent = Theme.accent.opacity(0.8)
        ZStack {
            Theme.ink.opacity(0.04)
            Group {
                switch layout {
                case .studio:
                    HStack(spacing: 3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Capsule().fill(accent).frame(height: 3)
                            ForEach(0..<4, id: \.self) { _ in Capsule().fill(block).frame(height: 3) }
                        }
                        .padding(3).frame(width: 18).frame(maxHeight: .infinity, alignment: .top)
                        .background(RoundedRectangle(cornerRadius: 3).fill(block.opacity(0.5)))
                        contentBlocks(block)
                    }
                case .sidebar:
                    HStack(spacing: 3) {
                        VStack(spacing: 3) {
                            Circle().fill(accent).frame(width: 4, height: 4)
                            ForEach(0..<4, id: \.self) { _ in Circle().fill(block).frame(width: 4, height: 4) }
                        }
                        .padding(.vertical, 3).frame(width: 9).frame(maxHeight: .infinity, alignment: .top)
                        .background(RoundedRectangle(cornerRadius: 3).fill(block.opacity(0.5)))
                        contentBlocks(block)
                    }
                case .tabs:
                    VStack(spacing: 3) {
                        HStack(spacing: 2) {
                            Capsule().fill(accent).frame(width: 12, height: 4)
                            ForEach(0..<5, id: \.self) { _ in Circle().fill(block).frame(width: 4, height: 4) }
                            Spacer(minLength: 0)
                        }
                        contentBlocks(block)
                    }
                case .classic:
                    VStack(spacing: 3) {
                        Capsule().fill(block).frame(width: 22, height: 3).frame(maxWidth: .infinity, alignment: .leading)
                        contentBlocks(block)
                        Capsule().fill(block).frame(width: 30, height: 5)
                    }
                case .minimal:
                    VStack(spacing: 3) {
                        HStack(spacing: 2) {
                            Capsule().fill(accent).frame(width: 18, height: 4)
                            Image(systemName: "chevron.down").font(.system(size: 4, weight: .bold)).foregroundStyle(block)
                            Spacer(minLength: 0)
                        }
                        RoundedRectangle(cornerRadius: 2).fill(block)
                    }
                case .launcher:
                    VStack(spacing: 2) {
                        ForEach(0..<2, id: \.self) { row in
                            HStack(spacing: 2) {
                                ForEach(0..<4, id: \.self) { col in
                                    RoundedRectangle(cornerRadius: 2).fill(row == 0 && col == 0 ? accent : block)
                                }
                            }
                        }
                    }
                }
            }
            .padding(5)
        }
    }

    private func contentBlocks(_ block: Color) -> some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2).fill(block).frame(height: 7)
            HStack(spacing: 2) {
                RoundedRectangle(cornerRadius: 2).fill(block)
                RoundedRectangle(cornerRadius: 2).fill(block).frame(width: 12)
            }
        }
    }
}

// The panel's outline for each notch shape, as it drops out of a black bar.
private struct ShapeSketch: View {
    let style: NotchStyle

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack(alignment: .top) {
                Theme.ink.opacity(0.04)
                Rectangle().fill(Color.black).frame(height: 6)
                NotchShape(style: style, neckWidth: w * 0.34, neckHeight: 6, radius: 6)
                    .fill(Theme.ink.opacity(0.18))
                    .frame(width: w * 0.72, height: h * 0.78)
                    .overlay(alignment: .top) {
                        NotchShape(style: style, neckWidth: w * 0.34, neckHeight: 6, radius: 6)
                            .stroke(Theme.accent.opacity(0.7), lineWidth: 1)
                            .frame(width: w * 0.72, height: h * 0.78)
                    }
            }
        }
    }
}
