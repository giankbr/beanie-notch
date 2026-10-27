import AppKit
import Combine
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home, today, prayer, shelf, clipboard, music, ai, controls, tools, settings
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .today: "calendar"
        case .prayer: "moon.fill"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .music: "music.note"
        case .ai: "sparkles"
        case .controls: "switch.2"
        case .tools: "wrench.and.screwdriver.fill"
        case .settings: "gearshape.fill"
        }
    }

    // Short enough for a side menu.
    var label: String {
        switch self {
        case .prayer: "Prayer"
        case .music: "Music"
        case .ai: "AI"
        default: title
        }
    }

    var title: String {
        switch self {
        case .home: "Overview"
        case .today: "Today"
        case .prayer: "Prayer Times"
        case .shelf: "Shelf"
        case .clipboard: "Clipboard"
        case .music: "Now Playing"
        case .ai: "AI"
        case .controls: "Controls"
        case .tools: "Tools"
        case .settings: "Settings"
        }
    }
}

// The output volume or the screen's brightness, shown in the closed notch for a moment after it changes.
struct LevelHUD: Equatable {
    let id = UUID()
    var level: Float
    var muted = false
    var brightness = false
}

// A short message shown in the closed notch, split around the camera: icon and `left` on one side, `right` on the other.
struct Notice: Equatable {
    let id = UUID()
    var icon: String
    var color: Color
    var left: String
    var right: String
    var duration: TimeInterval = 4
    // Shown even with notch alerts off: meetings, prayer times, the focus timer.
    var essential = false
    // Clicking the closed notch while this shows opens it (a chat app) instead of the panel.
    var open: URL?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var expanded = false {
        // The launcher starts from its grid every time the panel opens.
        didSet { if !expanded { launcherGrid = true } }
    }
    @Published var launcherGrid = true
    @Published var pinned = false
    @Published var dropTargeted = false
    @Published var dropToAirDrop = false
    @Published var dropToAI = false
    // A file dropped on Ask AI, waiting on the AI page.
    @Published var aiFile: URL?
    // Where Ask AI ends and AirDrop starts, as shares of the panel's width; set by the Shelf while a file is dragged.
    var dropSplit: (ai: CGFloat, airDrop: CGFloat) = (0.32, 0.68)
    @Published var tab: Tab = .home
    @Published var closedSize = CGSize(width: 190, height: 32)
    @Published private(set) var notice: Notice?
    @Published private(set) var volume: LevelHUD?

    var openSize: CGSize {
        let body = settings.size.body
        // Studio's labelled sidebar needs room of its own.
        var extra: CGFloat = settings.layout == .studio && settings.size != .mini ? 96 : 0
        if settings.notchStyle == .seamless { extra += NotchStyle.ear * 2 }
        return CGSize(width: body.width + extra, height: closedSize.height + body.height)
    }

    let settings = Settings()
    let prayer = PrayerTimes()
    let stats = SystemStats()
    let cleaner = Cleaner()
    let shelf = Shelf()
    let clipboard = ClipboardHistory()
    let media = MediaController()
    let focus = FocusTimer()
    let calendar = CalendarFeed()
    let power = PowerMonitor()
    let uninstaller = Uninstaller()
    let largeFiles = LargeFiles()
    let audio = AudioOutputMonitor()
    let tasks = TaskList()
    let weather = Weather()
    let phoneDrop = PhoneDrop()
    let keepAwake = KeepAwake()
    let downloads = DownloadWatcher()
    let toggles = QuickToggles()
    let shortcuts = ShortcutsRunner()
    let battery = BatteryInfo()
    let displays = Displays()
    let countdown = CountdownTimer()
    let worldClock = WorldClock()
    let notes = Notes()
    let updater = Updater()
    let aiUsage = AIUsage()
    let messages = MessageBadges()
    let claude = ClaudeBridge()
    let devRuns = DevRuns()
    let meeting = MeetingWatcher()
    let ambient = Ambient()
    let rates = Rates()
    let quakes = Quakes()
    let pet = NotchPet()
    lazy var smartCopy = SmartCopy(rates: rates)
    // Set by the controller: opens the panel and keeps it open (a permission request is waiting).
    var openPanel: (() -> Void)?
    private let volumeWatcher = VolumeWatcher()
    private let brightnessWatcher = BrightnessWatcher()
    private let keyboard = KeyboardWatcher()
    private let health = HealthReminders()
    private var sinks: Set<AnyCancellable> = []
    private let screenshots = ScreenshotWatcher()

    init() {
        let notify: (Notice) -> Void = { [weak self] in self?.show($0) }
        power.onNotice = notify
        audio.onNotice = notify
        calendar.onNotice = notify
        prayer.onNotice = { [weak self] n in if self?.prayerOn == true { self?.show(n) } }
        tasks.onNotice = notify
        keyboard.onNotice = notify
        health.onNotice = { [weak self] n in
            self?.show(n)
            if n.icon == "drop.fill" { self?.pet.thirst() }
        }
        phoneDrop.onFile = { [weak self] url in
            self?.shelf.add([url])
            self?.show(Notice(icon: "iphone", color: Theme.accent, left: "From phone", right: url.lastPathComponent))
        }
        media.onTrackChange = { [weak self] track in
            guard let self, settings.songFlash, !expanded else { return }
            let shown = Lyrics.clean(title: track.title, artist: track.artist)
            show(Notice(icon: "music.note", color: Theme.accent, left: shown.1.isEmpty ? track.app : shown.1,
                        right: shown.0.isEmpty ? track.title : shown.0, duration: 3.5, essential: true))
        }
        volumeWatcher.onChange = { [weak self] level, muted in
            guard let self, settings.volumeHUD, !expanded else { return }
            showVolume(LevelHUD(level: level, muted: muted))
        }
        brightnessWatcher.onChange = { [weak self] level in
            guard let self, settings.volumeHUD, !expanded else { return }
            showVolume(LevelHUD(level: level, brightness: true))
        }
        countdown.onDone = { [weak self] in
            NSSound(named: "Glass")?.play()
            self?.show(Notice(icon: "hourglass", color: Theme.accent, left: "Time's up", right: "Timer done", duration: 6, essential: true))
        }
        shortcuts.onDone = { [weak self] name, ok in
            self?.show(Notice(icon: ok ? "checkmark.circle.fill" : "xmark.octagon.fill", color: ok ? Theme.accent : Theme.red,
                              left: ok ? "Shortcut done" : "Shortcut failed", right: name))
        }
        updater.onNewVersion = { [weak self] version in
            self?.show(Notice(icon: "arrow.down.app.fill", color: Theme.accent2, left: "Beanotch \(version)",
                              right: "Click to update", duration: 15, essential: true, open: AppModel.installUpdate))
        }
        // AirPods and other Bluetooth headphones: their charge follows the "Connected" notice once it's known.
        audio.onBluetooth = { [weak self] name in
            Task {
                guard let device = await BatteryInfo.bluetooth().first(where: { $0.name == name }) else { return }
                let levels = device.levels.map { $0.label.isEmpty ? "\($0.percent)%" : "\($0.label) \($0.percent)%" }.joined(separator: "  ")
                self?.show(Notice(icon: name.localizedCaseInsensitiveContains("airpods") ? "airpodspro" : "headphones",
                                  color: Theme.accent2, left: name, right: levels, duration: 5))
            }
        }
        claude.onNotice = notify
        devRuns.onNotice = notify
        devRuns.start()
        claude.onRequest = { [weak self] in self?.openPanel?() }
        settings.$claudeBridge.sink { [weak self] on in self?.claude.setEnabled(on) }.store(in: &sinks)
        messages.onNew = { [weak self] badge in
            self?.show(Notice(icon: "bubble.left.and.bubble.right.fill", color: Theme.accent2, left: badge.name,
                              right: badge.count == 1 ? "New message" : "\(badge.count) unread", duration: 6, open: badge.app))
        }
        settings.$messageAlerts.sink { [weak self] on in
            guard let self else { return }
            messages.setEnabled(on)
            // Asked once; after that the Settings row offers it again.
            if on, !messages.trusted, !UserDefaults.standard.bool(forKey: "askedAccessibility") {
                UserDefaults.standard.set(true, forKey: "askedAccessibility")
                messages.requestAccess()
            }
        }.store(in: &sinks)
        settings.$messageAllApps.sink { [weak self] all in self?.messages.allApps = all }.store(in: &sinks)
        downloads.onDone = { [weak self] url in
            self?.show(Notice(icon: "arrow.down.circle.fill", color: Theme.accent, left: "Downloaded", right: url.lastPathComponent))
        }
        settings.$downloadsInNotch.sink { [weak self] on in self?.downloads.setEnabled(on) }.store(in: &sinks)
        // The focus sound plays through focus stretches only: not on breaks, and not while paused.
        focus.$endDate.combineLatest(focus.$phase, settings.$focusSound).sink { [weak self] end, phase, name in
            guard let self else { return }
            if end != nil, phase == .focus, let sound = Ambient.Sound(rawValue: name) { ambient.play(sound) } else { ambient.stop() }
        }.store(in: &sinks)
        smartCopy.onNotice = notify
        clipboard.onText = { [weak self] text in self?.smartCopy.check(text) }
        settings.$smartCopy.sink { [weak self] on in self?.smartCopy.enabled = on }.store(in: &sinks)
        // The prayer place's nearest listed city, for fuel prices by province.
        rates.city = { [weak self] in
            guard let place = self?.prayer.place else { return nil }
            return PrayerTimes.cities.min { PrayerTimes.distance($0, place.lat, place.lng) < PrayerTimes.distance($1, place.lat, place.lng) }?.name
        }
        quakes.onNotice = notify
        quakes.place = { [weak self] in self?.prayer.place }
        settings.$quakeAlerts.sink { [weak self] on in self?.quakes.setEnabled(on) }.store(in: &sinks)
        pet.stats = stats
        pet.playing = { [weak self] in self?.media.now?.playing == true }
        settings.$notchPet.sink { [weak self] on in self?.pet.setEnabled(on) }.store(in: &sinks)
        // Files put on the Shelf feed the pet.
        var shelfCount = shelf.items.count
        shelf.$items.dropFirst().sink { [weak self] items in
            if items.count > shelfCount { self?.pet.feed() }
            shelfCount = items.count
        }.store(in: &sinks)
        settings.$meetingMode.sink { [weak self] on in self?.meeting.setEnabled(on) }.store(in: &sinks)
        meeting.onEnd = { [weak self] length in
            guard let self else { return }
            let held = self.held
            self.held = []
            show(Notice(icon: "phone.down.fill", color: Theme.accent, left: "Call ended · \(DevRuns.duration(length))",
                        right: held.isEmpty ? "Nothing missed" : held.count == 1 ? "1 alert held" : "\(held.count) alerts held",
                        essential: true))
            // Then the last few that waited, one after another.
            for (i, n) in held.suffix(3).enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.5 * Double(i + 1)) { [weak self] in
                    MainActor.assumeIsolated { self?.show(n) }
                }
            }
        }
        settings.$hiddenTabs.sink { [weak self] hidden in
            guard let self, hidden.contains(tab.rawValue), tab != .settings else { return }
            tab = .home
            if hidden.contains(Tab.home.rawValue) { tab = Tab.allCases.first { !hidden.contains($0.rawValue) } ?? .settings }
        }.store(in: &sinks)
        settings.$keyboardAlerts.sink { [weak self] on in self?.keyboard.enabled = on }.store(in: &sinks)
        settings.$waterEvery.sink { [weak self] v in self?.health.waterEvery = v }.store(in: &sinks)
        settings.$eyeBreaks.sink { [weak self] v in self?.health.eyeBreaks = v }.store(in: &sinks)
        settings.$stretchEvery.sink { [weak self] v in self?.health.stretchEvery = v }.store(in: &sinks)
        focus.onDone = { [weak self] phase in
            NSSound(named: "Glass")?.play()
            self?.show(phase == .focus
                ? Notice(icon: "checkmark.circle.fill", color: Theme.accent, left: "Focus done", right: "Take a break", essential: true)
                : Notice(icon: "timer", color: Theme.accent2, left: "Break over", right: "Back to it", essential: true))
        }
        screenshots.onShot = { [weak self] url in
            guard let self else { return }
            guard settings.nameScreenshots else {
                shelf.add([url])
                show(Notice(icon: "camera.viewfinder", color: Theme.accent2, left: "Screenshot", right: "On the Shelf"))
                return
            }
            Task { await self.addNamedScreenshot(url) }
        }
        screenshots.setEnabled(settings.screenshotsToShelf)
        settingsSink = settings.$screenshotsToShelf.sink { [weak self] on in self?.screenshots.setEnabled(on) }
        lyricsSink = settings.$lyrics.sink { [weak self] on in
            self?.media.lyrics.enabled = on
            if !on { self?.media.lyrics.clear() }
        }
    }

    private var settingsSink: AnyCancellable?
    private var lyricsSink: AnyCancellable?

    // A notice's link that installs the update instead of opening a page.
    static let installUpdate = URL(string: "beanotch:update")!

    // Alerts that can wait, held while a call is on.
    private var held: [Notice] = []

    func show(_ n: Notice) {
        guard n.essential || settings.notchAlerts else { return }
        if meeting.inCall, !n.essential {
            held.append(n)
            return
        }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { notice = n }
        if n.icon != "music.note" { pet.surprise() }
        DispatchQueue.main.asyncAfter(deadline: .now() + n.duration) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.notice?.id == n.id else { return }
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) { self.notice = nil }
            }
        }
    }

    func showVolume(_ v: LevelHUD) {
        withAnimation(.smooth(duration: 0.25)) { volume = v }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.volume?.id == v.id else { return }
                withAnimation(.smooth(duration: 0.35)) { self.volume = nil }
            }
        }
    }

    var engine: Assistant.Engine { Assistant.Engine(rawValue: settings.aiEngine) ?? .onDevice }

    // A screenshot renamed after what it shows ("invoice-oktober-2026.png"), read and named on the Mac.
    private func addNamedScreenshot(_ url: URL) async {
        var target = url
        let words = await Assistant.text(in: url)
        if !words.isEmpty, let name = try? await Assistant.respond(
            "Screen text: " + String(words.prefix(1500)),
            instructions: "Name this screenshot. Reply with 2 to 5 lowercase words joined by hyphens, in the text's language, no extension.",
            engine: engine) {
            let slug = Assistant.slug(name)
            if !slug.isEmpty {
                let folder = url.deletingLastPathComponent(), ext = url.pathExtension
                var candidate = folder.appendingPathComponent(slug).appendingPathExtension(ext)
                var n = 2
                while FileManager.default.fileExists(atPath: candidate.path) {
                    candidate = folder.appendingPathComponent("\(slug)-\(n)").appendingPathExtension(ext); n += 1
                }
                screenshots.ignore(candidate)
                if (try? FileManager.default.moveItem(at: url, to: candidate)) != nil { target = candidate }
            }
        }
        shelf.add([target])
        show(Notice(icon: "camera.viewfinder", color: Theme.accent2, left: "Screenshot", right: target.lastPathComponent))
    }

    // Volume from a scroll over the notch, in steps like the keyboard's.
    func nudgeVolume(by delta: Float) {
        volumeWatcher.nudge(by: delta)
    }

    // The on-screen ruler; each measure is copied and shown in the notch.
    func measure() {
        expanded = false
        ScreenRuler.shared.onMeasure = { [weak self] size in
            self?.show(Notice(icon: "ruler", color: Theme.accent, left: "Copied", right: size, essential: true))
        }
        ScreenRuler.shared.show()
    }

    // Samples a color anywhere on screen with the system loupe, then copies its hex code.
    func pickColor() {
        expanded = false
        NSColorSampler().show { [weak self] color in
            guard let color else { return }
            MainActor.assumeIsolated {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(color.hex, forType: .string)
                self?.show(Notice(icon: "eyedropper.full", color: Color(nsColor: color), left: "Copied", right: color.hex, essential: true))
            }
        }
    }

    var showsMiniPlayer: Bool { settings.miniPlayer && media.now?.playing == true }
    // The line being sung, beside the notch, when that's switched on and the song has synced lyrics.
    var showsNotchLyrics: Bool { showsMiniPlayer && settings.lyricsInNotch && media.lyrics.state == .synced }

    var closedWidth: CGFloat {
        let extra: CGFloat = volume != nil ? 190 : notice.map(noticeWidth) ?? (meeting.inCall ? 200 : focus.isRunning ? 110
            : countdown.isRunning ? 110 : downloads.current != nil ? 240 : claude.working != nil ? 220 : devRuns.current != nil ? 240 : calendar.meeting != nil ? 240 : showsPrayerCountdown ? 170
            : showsNotchLyrics ? 340 : showsMiniPlayer ? 64 : 0)
        // The pet keeps a corner of the right side whatever shows; both sides grow so the camera stays centred.
        return closedSize.width + extra + (settings.notchPet ? NotchPet.slot * 2 : 0)
    }

    // Each side of the camera gets room for the longer of its two texts, so neither is cut short.
    private func noticeWidth(_ n: Notice) -> CGFloat {
        let longest = CGFloat(max(n.left.count + 3, n.right.count))
        return min(420, max(260, longest * 6.4 * 2 + 40))
    }

    var showsPrayerCountdown: Bool { prayerOn && settings.prayerCountdown && prayer.soon != nil }

    // The pages in the menus, without the ones switched off. Settings always stays.
    var visibleTabs: [Tab] { Tab.allCases.filter { $0 == .settings || !settings.hiddenTabs.contains($0.rawValue) } }

    // With the Prayer page off, everything about prayer goes: the header time, the countdown, the alerts, the
    // Hijri date.
    var prayerOn: Bool { !settings.hiddenTabs.contains(Tab.prayer.rawValue) }
    var closedHeight: CGFloat { closedSize.height }
}

extension View {
    func notchEnvironment(_ m: AppModel) -> some View {
        environmentObject(m)
            .environmentObject(m.stats)
            .environmentObject(m.cleaner)
            .environmentObject(m.shelf)
            .environmentObject(m.clipboard)
            .environmentObject(m.media)
            .environmentObject(m.focus)
            .environmentObject(m.calendar)
            .environmentObject(m.power)
            .environmentObject(m.uninstaller)
            .environmentObject(m.largeFiles)
            .environmentObject(m.settings)
            .environmentObject(m.prayer)
            .environmentObject(m.audio)
            .environmentObject(m.media.lyrics)
            .environmentObject(m.tasks)
            .environmentObject(m.weather)
            .environmentObject(m.phoneDrop)
            .environmentObject(m.keepAwake)
            .environmentObject(m.downloads)
            .environmentObject(m.toggles)
            .environmentObject(m.shortcuts)
            .environmentObject(m.battery)
            .environmentObject(m.displays)
            .environmentObject(m.countdown)
            .environmentObject(m.worldClock)
            .environmentObject(m.notes)
            .environmentObject(m.updater)
            .environmentObject(m.aiUsage)
            .environmentObject(m.messages)
            .environmentObject(m.claude)
            .environmentObject(m.devRuns)
            .environmentObject(m.meeting)
            .environmentObject(m.rates)
            .environmentObject(m.pet)
    }
}

func formatBytes(_ bytes: Int64) -> String {
    bytes <= 0 ? "0 KB" : ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

func formatMemory(_ bytes: UInt64) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .memory)
}

func formatRate(_ bytesPerSecond: Int64) -> String {
    bytesPerSecond < 1024 ? "0 KB/s" : ByteCountFormatter.string(fromByteCount: bytesPerSecond, countStyle: .file) + "/s"
}

func formatClock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded(.down)))
    return String(format: "%d:%02d", s / 60, s % 60)
}
