import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: Settings
    @EnvironmentObject var clipboard: ClipboardHistory
    @EnvironmentObject var prayer: PrayerTimes
    @EnvironmentObject var updater: Updater
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    private static let delays: [Double] = [0.6, 1.2, 2.5]
    private static let reminders = [0, 5, 10, 15]
    private static let waterSteps = [0, 30, 60, 90]
    private static let stretchSteps = [0, 45, 60, 90]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                section("Appearance")
                card {
                    row("circle.lefthalf.filled", "Theme", "The notch itself always stays black") {
                        Segmented(options: ThemeMode.allCases.map(\.title), selection: index($settings.theme, ThemeMode.allCases))
                    }
                    row("paintpalette", "Accent", "Buttons, highlights and the mini player") {
                        HStack(spacing: 6) {
                            ForEach(AccentChoice.allCases, id: \.self) { choice in
                                Button { settings.accent = choice } label: {
                                    Circle().fill(choice.primary).frame(width: 14, height: 14)
                                        .overlay(Circle().strokeBorder(Theme.ink.opacity(settings.accent == choice ? 0.9 : 0), lineWidth: 2))
                                        .padding(2)
                                        .contentShape(Circle())
                                }
                                .buttonStyle(.plain)
                                .help(choice.rawValue.capitalized)
                            }
                        }
                    }
                    row("sidebar.left", "Layout", "Where the tabs sit") {
                        Segmented(options: LayoutStyle.allCases.map(\.title), selection: index($settings.layout, LayoutStyle.allCases))
                    }
                    row("arrow.up.left.and.arrow.down.right", "Panel size", "How big the panel opens") {
                        Segmented(options: PanelSize.allCases.map(\.title), selection: index($settings.size, PanelSize.allCases))
                    }
                    row("textformat", "Font", "SF Pro matches the icons; Be Vietnam Pro is rounder") {
                        Segmented(options: ["SF Pro", "Be Vietnam Pro"], selection: Binding(get: { settings.systemFont ? 0 : 1 },
                                                                                          set: { settings.systemFont = $0 == 0 }))
                    }
                    row("capsule.portrait", "Notch shape", "How the panel opens out of the notch") {
                        Segmented(options: NotchStyle.allCases.map(\.title), selection: index($settings.notchStyle, NotchStyle.allCases))
                    }

                }
                section("Notch")
                card {
                    row("cursorarrow.motionlines", "Open on hover", "Off: click the notch or press ⌥ Space") {
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
                    row("arrow.up.left.and.arrow.down.right.rectangle", "Hide in full screen", "Out of the way during videos and presentations") {
                        Toggle("", isOn: $settings.hideInFullScreen)
                    }
                    row("music.note.list", "Song changes", "The new song's title shows in the notch for a moment") {
                        Toggle("", isOn: $settings.songFlash)
                    }
                    row("text.quote", "Lyrics in the notch", "The line being sung, beside the notch, while it's closed") {
                        Toggle("", isOn: $settings.lyricsInNotch)
                    }
                    row("speaker.wave.2", "Volume & brightness", "The level shows in the notch when it changes") {
                        Toggle("", isOn: $settings.volumeHUD)
                    }
                    row("arrow.down.circle", "Downloads", "Progress of browser downloads in Downloads, and when they finish") {
                        Toggle("", isOn: $settings.downloadsInNotch)
                    }
                    row("hand.draw", "Gestures", "Over the notch: swipe sideways to change song, scroll for volume") {
                        Toggle("", isOn: $settings.gestures)
                    }
                    row("capslock", "Keyboard", "Caps Lock and keyboard language changes") {
                        Toggle("", isOn: $settings.keyboardAlerts)
                    }
                    row("music.note", "Mini player", "Artwork and bars beside the notch while music plays") {
                        Toggle("", isOn: $settings.miniPlayer)
                    }
                    row("quote.bubble", "Lyrics", "From LRCLIB, NetEase, QQ Music and Kugou: the song's title and artist are sent to look them up") {
                        Toggle("", isOn: $settings.lyrics)
                    }
                    row("bell.badge", "Notch alerts", "Charging, low battery, headphones, screenshots") {
                        Toggle("", isOn: $settings.notchAlerts)
                    }

                }
                section("Shelf & Clipboard")
                card {
                    row("camera.viewfinder", "Screenshots to Shelf", "New screenshots land on the Shelf, ready to drag") {
                        Toggle("", isOn: $settings.screenshotsToShelf)
                    }
                    row("doc.on.clipboard", "Clipboard history", "Keeps the last 100 texts and images you copy") {
                        Toggle("", isOn: $clipboard.enabled)
                    }

                }
                section("Wellbeing")
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

                section("Prayer times")
                card {
                    row("location", "Location", prayer.place?.name ?? "Not set") {
                        CityMenu(label: "Change")
                    }
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
                section("System")
                card {
                    row("power", "Open at login", loginError ?? "Start Notchy when you log in") {
                        Toggle("", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, on in setLaunchAtLogin(on) }
                    }
                    row("arrow.down.app", "Updates", updateCaption) {
                        HStack(spacing: 8) {
                            if updater.updateAvailable, let page = updater.page {
                                PillButton(text: "Get \(updater.latest ?? "")", color: Theme.accent) { NSWorkspace.shared.open(page) }
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
                HStack {
                    Text("Notchy \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")")
                        .font(.app(size: 9)).foregroundStyle(Theme.faint)
                    Spacer()
                    PillButton(text: "Quit Notchy", icon: "xmark", color: Theme.red) { NSApp.terminate(nil) }
                }
                .padding(.top, 4)
            }
        }
        .scrollIndicators(.never)
    }

    private func index<T: Equatable>(_ value: Binding<T>, _ all: [T]) -> Binding<Int> {
        Binding(get: { all.firstIndex(of: value.wrappedValue) ?? 0 }, set: { value.wrappedValue = all[$0] })
    }

    private func section(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.app(size: 8.5, weight: .semibold))
            .tracking(0.9)
            .foregroundStyle(Theme.faint)
            .padding(.top, 8)
            .padding(.leading, 4)
    }

    // One card per section; rows are split by hairlines, the first one hidden under the card's edge.
    private var updateCaption: String {
        if updater.failed { return "Couldn't reach GitHub (the repository must be public)" }
        if updater.updateAvailable { return "Notchy \(updater.latest ?? "") is out, you have \(updater.current)" }
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
            loginError = "Move Notchy to Applications first"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
