import AppKit
import Combine
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case home, today, prayer, shelf, clipboard, music, tools, settings
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "square.grid.2x2.fill"
        case .today: "calendar"
        case .prayer: "moon.fill"
        case .shelf: "tray.full.fill"
        case .clipboard: "doc.on.clipboard.fill"
        case .music: "music.note"
        case .tools: "wrench.and.screwdriver.fill"
        case .settings: "gearshape.fill"
        }
    }

    // Short enough for a side menu.
    var label: String {
        switch self {
        case .prayer: "Prayer"
        case .music: "Music"
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
}

@MainActor
final class AppModel: ObservableObject {
    @Published var expanded = false
    @Published var pinned = false
    @Published var dropTargeted = false
    @Published var dropToAirDrop = false
    @Published var tab: Tab = .home
    @Published var closedSize = CGSize(width: 190, height: 32)
    @Published private(set) var notice: Notice?
    @Published private(set) var volume: LevelHUD?

    var openSize: CGSize {
        let body = settings.size.body
        // Studio's labelled sidebar needs room of its own.
        var extra: CGFloat = settings.layout == .studio ? 96 : 0
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
        prayer.onNotice = notify
        tasks.onNotice = notify
        keyboard.onNotice = notify
        health.onNotice = notify
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
        downloads.onDone = { [weak self] url in
            self?.show(Notice(icon: "arrow.down.circle.fill", color: Theme.accent, left: "Downloaded", right: url.lastPathComponent))
        }
        settings.$downloadsInNotch.sink { [weak self] on in self?.downloads.setEnabled(on) }.store(in: &sinks)
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
            self?.shelf.add([url])
            self?.show(Notice(icon: "camera.viewfinder", color: Theme.accent2, left: "Screenshot", right: "On the Shelf"))
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

    func show(_ n: Notice) {
        guard n.essential || settings.notchAlerts else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { notice = n }
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
        let extra: CGFloat = volume != nil ? 190 : notice != nil ? 260 : focus.isRunning ? 110
            : downloads.current != nil ? 240 : calendar.meeting != nil ? 240 : showsPrayerCountdown ? 170
            : showsNotchLyrics ? 340 : showsMiniPlayer ? 64 : 0
        return closedSize.width + extra
    }

    var showsPrayerCountdown: Bool { settings.prayerCountdown && prayer.soon != nil }
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
