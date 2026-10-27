import AppKit
import SwiftUI

enum ThemeMode: String, CaseIterable {
    case system, light, dark, midnight, glass

    var title: String { rawValue.capitalized }

    var appearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark, .midnight, .glass: NSAppearance(named: .darkAqua)
        }
    }
}

enum LayoutStyle: String, CaseIterable {
    case studio, sidebar, tabs, classic, minimal, launcher

    var title: String {
        switch self {
        case .classic: "Classic"
        case .studio: "Studio"
        case .sidebar: "Compact"
        case .tabs: "Top tabs"
        case .minimal: "Minimal"
        case .launcher: "Launcher"
        }
    }

    var caption: String {
        switch self {
        case .studio: "Labelled side menu"
        case .sidebar: "Icon rail"
        case .tabs: "Tabs along the top"
        case .classic: "Greeting and a dock"
        case .minimal: "Just the page; switch from the title"
        case .launcher: "A grid of tiles to start from"
        }
    }
}

enum PanelSize: String, CaseIterable {
    case mini, compact, regular, large

    var title: String { rawValue.capitalized }

    // Mini matches the open size of the common notch apps (about 640 × 200 with the notch row).
    var body: CGSize {
        switch self {
        case .mini: CGSize(width: 640, height: 168)
        case .compact: CGSize(width: 600, height: 270)
        case .regular: CGSize(width: 680, height: 300)
        case .large: CGSize(width: 780, height: 350)
        }
    }
}

enum AccentChoice: String, CaseIterable {
    case mint, ocean, sunset, rose, lime, violet, teal, gold, crimson, graphite

    var primary: Color {
        switch self {
        case .mint: Color(red: 0.33, green: 0.86, blue: 0.68)
        case .ocean: Color(red: 0.3, green: 0.62, blue: 1.0)
        case .sunset: Color(red: 1.0, green: 0.58, blue: 0.3)
        case .rose: Color(red: 1.0, green: 0.42, blue: 0.6)
        case .lime: Color(red: 0.62, green: 0.86, blue: 0.24)
        case .violet: Color(red: 0.6, green: 0.48, blue: 1.0)
        case .teal: Color(red: 0.2, green: 0.78, blue: 0.82)
        case .gold: Color(red: 0.95, green: 0.76, blue: 0.3)
        case .crimson: Color(red: 0.94, green: 0.33, blue: 0.36)
        case .graphite: Color(red: 0.62, green: 0.65, blue: 0.7)
        }
    }

    var secondary: Color {
        switch self {
        case .mint: Color(red: 0.6, green: 0.5, blue: 1.0)
        case .ocean: Color(red: 0.25, green: 0.8, blue: 0.9)
        case .sunset: Color(red: 0.95, green: 0.4, blue: 0.55)
        case .rose: Color(red: 0.62, green: 0.5, blue: 1.0)
        case .lime: Color(red: 0.25, green: 0.75, blue: 0.7)
        case .violet: Color(red: 0.95, green: 0.45, blue: 0.75)
        case .teal: Color(red: 0.45, green: 0.6, blue: 1.0)
        case .gold: Color(red: 1.0, green: 0.55, blue: 0.35)
        case .crimson: Color(red: 1.0, green: 0.62, blue: 0.3)
        case .graphite: Color(red: 0.45, green: 0.7, blue: 1.0)
        }
    }
}

// SF Pro is the system's; the others ship in the app (all under the SIL Open Font License) and match the Windows app.
enum AppFont: String, CaseIterable {
    case system, beVietnam, inter, jakarta

    var title: String {
        switch self {
        case .system: "SF Pro"
        case .beVietnam: "Be Vietnam"
        case .inter: "Inter"
        case .jakarta: "Jakarta"
        }
    }

    // The bundled files' PostScript name prefix, as in "Inter-SemiBold".
    var prefix: String? {
        switch self {
        case .system: nil
        case .beVietnam: "BeVietnamPro"
        case .inter: "Inter"
        case .jakarta: "PlusJakartaSans"
        }
    }
}

@MainActor
final class Settings: ObservableObject {
    private static let defaults = UserDefaults.standard

    @Published var theme: ThemeMode {
        didSet {
            save(theme.rawValue, "theme")
            applyAccent()
        }
    }
    @Published var layout: LayoutStyle { didSet { save(layout.rawValue, "layout") } }
    @Published var size: PanelSize { didSet { save(size.rawValue, "size") } }
    @Published var accent: AccentChoice {
        didSet {
            save(accent.rawValue, "accent")
            applyAccent()
        }
    }
    @Published var openOnHover: Bool { didSet { save(openOnHover, "openOnHover") } }
    @Published var closeDelay: Double { didSet { save(closeDelay, "closeDelay") } }
    @Published var miniPlayer: Bool { didSet { save(miniPlayer, "miniPlayer") } }
    @Published var notchAlerts: Bool { didSet { save(notchAlerts, "notchAlerts") } }
    @Published var hotkey: Bool { didSet { save(hotkey, "hotkey") } }
    // The shortcut as Carbon wants it (virtual key code and modifier mask), and how it reads on screen.
    @Published private(set) var hotkeyCode: Int
    @Published private(set) var hotkeyModifiers: Int
    @Published private(set) var hotkeyLabel: String
    @Published var screenshotsToShelf: Bool { didSet { save(screenshotsToShelf, "screenshotsToShelf") } }
    @Published var lyrics: Bool { didSet { save(lyrics, "lyrics") } }
    @Published var font: AppFont {
        didSet {
            save(font.rawValue, "font")
            Theme.font = font
        }
    }
    @Published var prayerCountdown: Bool { didSet { save(prayerCountdown, "prayerCountdown") } }
    @Published var notchStyle: NotchStyle { didSet { save(notchStyle.rawValue, "notchStyle") } }
    @Published var hideInFullScreen: Bool { didSet { save(hideInFullScreen, "hideInFullScreen") } }
    @Published var songFlash: Bool { didSet { save(songFlash, "songFlash") } }
    @Published var lyricsInNotch: Bool { didSet { save(lyricsInNotch, "lyricsInNotch") } }
    @Published var keyboardAlerts: Bool { didSet { save(keyboardAlerts, "keyboardAlerts") } }
    @Published var volumeHUD: Bool { didSet { save(volumeHUD, "volumeHUD") } }
    @Published var gestures: Bool { didSet { save(gestures, "gestures") } }
    @Published var aiEngine: String { didSet { save(aiEngine, "aiEngine") } }
    @Published var nameScreenshots: Bool { didSet { save(nameScreenshots, "nameScreenshots") } }
    @Published var claudeBridge: Bool { didSet { save(claudeBridge, "claudeBridge") } }
    // Pages switched off in Settings › Pages, by their raw names.
    @Published var hiddenTabs: Set<String> { didSet { Self.defaults.set(Array(hiddenTabs).sorted(), forKey: "hiddenTabs") } }
    @Published var messageAlerts: Bool { didSet { save(messageAlerts, "messageAlerts") } }
    @Published var messageAllApps: Bool { didSet { save(messageAllApps, "messageAllApps") } }
    @Published var downloadsInNotch: Bool { didSet { save(downloadsInNotch, "downloadsInNotch") } }
    @Published var meetingMode: Bool { didSet { save(meetingMode, "meetingMode") } }
    @Published var smartCopy: Bool { didSet { save(smartCopy, "smartCopy") } }
    @Published var quakeAlerts: Bool { didSet { save(quakeAlerts, "quakeAlerts") } }
    @Published var notchPet: Bool { didSet { save(notchPet, "notchPet") } }
    @Published var petKind: PetKind { didSet { save(petKind.rawValue, "petKind") } }
    // The sound that plays while a focus stretch runs; empty for none.
    @Published var focusSound: String { didSet { save(focusSound, "focusSound") } }
    @Published var waterEvery: Int { didSet { save(waterEvery, "waterEvery") } }
    @Published var eyeBreaks: Bool { didSet { save(eyeBreaks, "eyeBreaks") } }
    @Published var stretchEvery: Int { didSet { save(stretchEvery, "stretchEvery") } }

    // Changes whenever the look changes, so the panel can rebuild with the new colors.
    var styleKey: String { "\(theme.rawValue)-\(accent.rawValue)-\(layout.rawValue)-\(notchStyle.rawValue)-\(font.rawValue)" }

    init() {
        let d = Self.defaults
        theme = ThemeMode(rawValue: d.string(forKey: "theme") ?? "") ?? .dark
        layout = LayoutStyle(rawValue: d.string(forKey: "layout") ?? "") ?? .studio
        size = PanelSize(rawValue: d.string(forKey: "size") ?? "") ?? .regular
        accent = AccentChoice(rawValue: d.string(forKey: "accent") ?? "") ?? .mint
        openOnHover = d.object(forKey: "openOnHover") as? Bool ?? true
        closeDelay = d.object(forKey: "closeDelay") as? Double ?? 1.2
        miniPlayer = d.object(forKey: "miniPlayer") as? Bool ?? true
        notchAlerts = d.object(forKey: "notchAlerts") as? Bool ?? true
        hotkey = d.object(forKey: "hotkey") as? Bool ?? true
        hotkeyCode = d.object(forKey: "hotkeyCode") as? Int ?? 49
        hotkeyModifiers = d.object(forKey: "hotkeyModifiers") as? Int ?? 2048
        hotkeyLabel = d.string(forKey: "hotkeyLabel") ?? "⌥ Space"
        screenshotsToShelf = d.object(forKey: "screenshotsToShelf") as? Bool ?? true
        lyrics = d.object(forKey: "lyrics") as? Bool ?? true
        // Earlier versions had a single switch between SF Pro and Be Vietnam Pro.
        font = AppFont(rawValue: d.string(forKey: "font") ?? "") ?? ((d.object(forKey: "systemFont") as? Bool ?? true) ? .system : .beVietnam)
        prayerCountdown = d.object(forKey: "prayerCountdown") as? Bool ?? true
        notchStyle = NotchStyle(rawValue: d.string(forKey: "notchStyle") ?? "") ?? .drop
        hideInFullScreen = d.object(forKey: "hideInFullScreen") as? Bool ?? true
        songFlash = d.object(forKey: "songFlash") as? Bool ?? true
        lyricsInNotch = d.object(forKey: "lyricsInNotch") as? Bool ?? true
        keyboardAlerts = d.object(forKey: "keyboardAlerts") as? Bool ?? true
        volumeHUD = d.object(forKey: "volumeHUD") as? Bool ?? true
        gestures = d.object(forKey: "gestures") as? Bool ?? true
        aiEngine = d.string(forKey: "aiEngine") ?? (Assistant.onDeviceAvailable ? "onDevice" : "claude")
        nameScreenshots = d.bool(forKey: "nameScreenshots")
        claudeBridge = d.bool(forKey: "claudeBridge")
        hiddenTabs = Set(d.stringArray(forKey: "hiddenTabs") ?? [])
        messageAlerts = d.object(forKey: "messageAlerts") as? Bool ?? true
        messageAllApps = d.bool(forKey: "messageAllApps")
        downloadsInNotch = d.object(forKey: "downloadsInNotch") as? Bool ?? true
        meetingMode = d.object(forKey: "meetingMode") as? Bool ?? true
        smartCopy = d.object(forKey: "smartCopy") as? Bool ?? true
        quakeAlerts = d.object(forKey: "quakeAlerts") as? Bool ?? true
        notchPet = d.bool(forKey: "notchPet")
        petKind = PetKind(rawValue: d.string(forKey: "petKind") ?? "") ?? .bean
        focusSound = d.string(forKey: "focusSound") ?? ""
        waterEvery = d.object(forKey: "waterEvery") as? Int ?? 0
        eyeBreaks = d.bool(forKey: "eyeBreaks")
        stretchEvery = d.object(forKey: "stretchEvery") as? Int ?? 0
        applyAccent()
        Theme.font = font
    }

    func setHotkey(code: Int, modifiers: Int, label: String) {
        hotkeyCode = code
        hotkeyModifiers = modifiers
        hotkeyLabel = label
        save(code, "hotkeyCode")
        save(modifiers, "hotkeyModifiers")
        save(label, "hotkeyLabel")
    }

    private func applyAccent() {
        Theme.mode = theme
        Theme.accent = accent.primary
        Theme.accent2 = accent.secondary
    }

    private func save(_ value: Any, _ key: String) {
        Self.defaults.set(value, forKey: key)
    }
}
