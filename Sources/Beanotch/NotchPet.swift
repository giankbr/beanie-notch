import AppKit
import SwiftUI

// A coffee bean that lives in the right corner of the closed notch, whatever else shows there, and reacts to the Mac:
// it dozes when nobody's there, sweats when the processor is flat out, munches files put on the Shelf, wants water
// when it's time to drink, bobs along to music, jumps at each alert and yawns when you're up past midnight.
@MainActor
final class NotchPet: ObservableObject {
    enum Mood: Equatable {
        case happy, sleepy, panic, eating, thirsty, dancing, surprised, late
        case love, dizzy, sad, party, focus, coffee, tired, charged, hungry, sway, walking
    }

    // The room it takes beside the notch's content, in points.
    static let slot: CGFloat = 38

    @Published private(set) var mood: Mood = .happy
    // 0 at home in its corner, 1 at the far end of the notch; the view animates between them.
    @Published private(set) var walk: CGFloat = 0
    // Points from focus sessions, feeding, petting and good days; every ten is a level, and levels unlock things to wear.
    @Published private(set) var xp = UserDefaults.standard.integer(forKey: "petXP") {
        didSet { UserDefaults.standard.set(xp, forKey: "petXP") }
    }
    // Wearing the cap for prayer, for a while after the call.
    @Published private(set) var praying = false
    var level: Int { min(xp / 10 + 1, 9) }

    var stats: SystemStats?
    var playing: (() -> Bool)?
    var focusPhase: (() -> FocusTimer.Phase?)?
    var battery: (() -> (percent: Int, plugged: Bool)?)?
    // Whether the closed notch has nothing else on it, so the pet can stroll across.
    var notchIsFree: (() -> Bool)?
    var onLevelUp: ((Int) -> Void)?
    private var timer: Timer?
    private var reaction: (mood: Mood, until: Date)?
    private var taps: [Date] = []
    private var prayingUntil = Date.distantPast
    private var fedDay: String {
        get { UserDefaults.standard.string(forKey: "petFedDay") ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "petFedDay") }
    }
    private static var today: String { Date().formatted(.iso8601.year().month().day()) }

    func setEnabled(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        let t = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        // A point for each day it's kept company.
        if UserDefaults.standard.string(forKey: "petSeenDay") != Self.today {
            UserDefaults.standard.set(Self.today, forKey: "petSeenDay")
            gain(1)
        }
        update()
    }

    // MARK: Things done to it

    // A click: it hops and shows a heart, takes its meal if it was hungry, and gets dizzy from five in a row.
    func tap() {
        let now = Date()
        taps = taps.filter { now.timeIntervalSince($0) < 1.5 } + [now]
        if taps.count >= 5 {
            taps = []
            react(.dizzy, for: 3)
        } else if mood == .hungry {
            fedDay = Self.today
            gain(1)
            react(.eating, for: 3)
        } else {
            react(.love, for: 1.6)
        }
    }

    // The pointer resting on it for a moment.
    func stroke() {
        react(.love, for: 2.5)
        let key = "petStrokedHour", hour = Int(Date().timeIntervalSince1970 / 3600)
        if UserDefaults.standard.integer(forKey: key) != hour {
            UserDefaults.standard.set(hour, forKey: key)
            gain(1)
        }
    }

    func sway() { react(.sway, for: 1.5) }
    func shake() { react(.dizzy, for: 3) }

    // A file dropped on it, or put on the Shelf.
    func feed() {
        if fedDay != Self.today { fedDay = Self.today; gain(1) }
        react(.eating, for: 4)
    }

    func surprise() { react(.surprised, for: 2.5) }

    func thirst() { react(.thirsty, for: 60) }

    // What a notice means to it: a failed command makes it sad, a finished one or a finished focus session is a
    // party, a quake shakes it, a charger gives it a jolt, the call to prayer puts its cap on. Anything else startles.
    func react(to n: Notice, prayerCap: Bool) {
        switch n.icon {
        case "music.note": return
        case "xmark.octagon.fill": react(.sad, for: 6)
        case "checkmark.circle.fill":
            react(.party, for: 4)
            if n.left == "Focus done" { gain(2) } else if n.left.hasPrefix("Done") { gain(1) }
        case "waveform.path.ecg", "water.waves": react(.panic, for: 8)
        case "bolt.fill": react(.charged, for: 4)
        case "drop.fill": thirst()
        case "moon.fill", "fork.knife":
            if prayerCap { prayingUntil = Date().addingTimeInterval(10 * 60); update() }
            surprise()
        default: surprise()
        }
    }

    private func react(_ mood: Mood, for seconds: TimeInterval) {
        guard timer != nil else { return }
        reaction = (mood, Date().addingTimeInterval(seconds))
        update()
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.1) { [weak self] in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    private func gain(_ points: Int) {
        let before = level
        xp += points
        if level > before { onLevelUp?(level) }
    }

    // Now and then, with nothing else going on, it walks to the other end of the notch and back.
    private func stroll() {
        guard walk == 0, notchIsFree?() == true else { return }
        walk = 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            MainActor.assumeIsolated {
                self?.walk = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                    MainActor.assumeIsolated { self?.update() }
                }
            }
        }
    }

    private func update() {
        let now = Date()
        stats?.refresh()
        if let r = reaction, now >= r.until { reaction = nil }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let hour = Calendar.current.component(.hour, from: now)
        let power = battery?()
        let phase = focusPhase?()
        if praying != (now < prayingUntil) { praying = now < prayingUntil }
        var next: Mood = reaction?.mood
            ?? ((stats?.cpu ?? 0) > 0.85 ? .panic
            : power.map { $0.percent < 20 && !$0.plugged } == true ? .tired
            : phase == .focus ? .focus
            : phase == .rest ? .coffee
            : idle > 180 ? .sleepy
            : playing?() == true ? .dancing
            : hour >= 10 && fedDay != Self.today ? .hungry
            : hour < 4 ? .late
            : .happy)
        if walk > 0 && next == .happy { next = .walking }
        if next != mood { mood = next }
        if next == .happy, idle < 60, Int.random(in: 0..<60) == 0 { stroll() }
    }
}

// Things to wear, unlocked by level; the cap for prayer and the focus headband come on by themselves.
enum PetAccessory: String, CaseIterable, Identifiable {
    case none, scarf, glasses, cap, crown
    var id: String { rawValue }
    var title: String { self == .none ? "Nothing" : rawValue.capitalized }
    var level: Int {
        switch self {
        case .none: 1
        case .scarf: 2
        case .glasses: 3
        case .cap: 4
        case .crown: 6
        }
    }
}

// The pets to pick from, each a pixel to a character ("#" body, "-" shade), with where its eyes and mouth sit.
enum PetKind: String, CaseIterable, Identifiable {
    case bean, cat, frog, ghost
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var shape: [String] {
        switch self {
        case .bean: ["....####....", "..########..", ".##########.", ".##########.", "############",
                     "############", "############", ".#######-##.", "..#####-##..", "....##-#...."]
        case .cat: [".#........#.", ".##......##.", ".####--####.", "############", "############",
                    "############", "############", ".##########.", "..########..", "..##....##.."]
        case .frog: [".###....###.", "#####..#####", "############", "############", "############",
                     "############", ".##########.", ".##########.", "..##....##..", "............"]
        case .ghost: ["...######...", "..########..", ".##########.", ".##########.", ".##########.",
                      ".##########.", ".##########.", ".##########.", ".###.##.###.", ".#...#...#.."]
        }
    }

    var body: Color {
        switch self {
        case .bean: Color(red: 0.62, green: 0.4, blue: 0.26)
        case .cat: Color(red: 0.96, green: 0.6, blue: 0.26)
        case .frog: Color(red: 0.42, green: 0.76, blue: 0.36)
        case .ghost: Color(red: 0.92, green: 0.92, blue: 1)
        }
    }

    var shade: Color {
        switch self {
        case .bean: Color(red: 0.36, green: 0.22, blue: 0.14)
        case .cat: Color(red: 0.74, green: 0.38, blue: 0.14)
        case .frog: Color(red: 0.2, green: 0.48, blue: 0.2)
        case .ghost: Color(red: 0.32, green: 0.3, blue: 0.45)
        }
    }

    // The white of the eye and the pupil; the ghost's are the other way round.
    var socket: Color { self == .ghost ? Color(red: 0.16, green: 0.15, blue: 0.26) : .white }
    var pupil: Color { self == .ghost ? .white : Color(red: 0.12, green: 0.08, blue: 0.06) }

    // Each eye's top-left pixel, and the middle of the mouth.
    var eyes: [CGPoint] {
        switch self {
        case .frog: [CGPoint(x: 1.5, y: 0.5), CGPoint(x: 8.5, y: 0.5)]
        case .cat: [CGPoint(x: 2.5, y: 3.5), CGPoint(x: 7.5, y: 3.5)]
        default: [CGPoint(x: 2.5, y: 3), CGPoint(x: 7.5, y: 3)]
        }
    }

    var mouth: CGPoint {
        switch self {
        case .frog: CGPoint(x: 6, y: 4.8)
        case .cat: CGPoint(x: 6, y: 6.3)
        default: CGPoint(x: 6, y: 6.5)
        }
    }
}

struct PetView: View {
    let mood: NotchPet.Mood
    var kind: PetKind = .bean
    var accessory: PetAccessory = .none
    var praying = false
    // How far right of the screen's centre the pet sits, so its eyes can follow the pointer; nil looks straight ahead.
    var offset: CGFloat?

    private static let pixel: CGFloat = 1.9

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.125)) { context in
            let frame = Int(context.date.timeIntervalSinceReferenceDate * 8)
            let look = look()
            Canvas { g, _ in draw(&g, frame: frame, look: look) }
                .frame(width: 18 * Self.pixel, height: 14 * Self.pixel)
        }
    }

    // Where the pointer is from the pet, as -1…1 across and down.
    private func look() -> CGPoint {
        guard let offset, let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else { return .zero }
        let mouse = NSEvent.mouseLocation
        let pet = CGPoint(x: screen.frame.midX + offset, y: screen.frame.maxY - 16)
        return CGPoint(x: max(-1, min(1, (mouse.x - pet.x) / 160)), y: max(-1, min(1, (pet.y - mouse.y) / 120)))
    }

    private func draw(_ g: inout GraphicsContext, frame: Int, look: CGPoint) {
        let p = Self.pixel
        // Moves: a bob to music, a jump at an alert, a shake when panicking, slow breathing otherwise.
        var dx: CGFloat = 0, dy: CGFloat = 2
        switch mood {
        case .dancing: dy = frame % 4 < 2 ? 1 : 3
        case .surprised: dy = frame % 6 < 3 ? 0.5 : 1.5
        case .panic: dx = frame % 2 == 0 ? -0.5 : 0.5
        case .sleepy, .tired: dy = frame % 32 < 16 ? 2 : 2.5
        case .love, .party, .charged: dy = frame % 8 < 4 ? 0.8 : 2
        case .walking: dy = frame % 4 < 2 ? 1.6 : 2.2
        case .sway: dx = sin(CGFloat(frame) * 0.9) * 1.2
        case .dizzy: dx = sin(CGFloat(frame) * 0.5) * 0.6
        default: dy = frame % 24 < 12 ? 2 : 2.3
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ color: Color, w: CGFloat = 1, h: CGFloat = 1) {
            // A hair larger than the grid, so no seams show between pixels.
            g.fill(Path(CGRect(x: (x + 3 + dx) * p, y: (y + dy) * p, width: w * p + 0.3, height: h * p + 0.3)), with: .color(color))
        }
        for (y, row) in kind.shape.enumerated() {
            for (x, c) in row.enumerated() where c != "." {
                dot(CGFloat(x), CGFloat(y), c == "-" ? kind.shade : kind.body)
            }
        }
        if kind != .ghost { dot(kind == .frog ? 4 : 2, 2, .white.opacity(0.35)) }
        func heart(at o: CGPoint) {
            let red = Color(red: 1, green: 0.35, blue: 0.45)
            dot(o.x, o.y, red); dot(o.x + 2, o.y, red); dot(o.x, o.y + 1, red, w: 3); dot(o.x + 1, o.y + 2, red)
        }

        let blush = Color(red: 1, green: 0.5, blue: 0.55).opacity(0.6)
        let water = Color(red: 0.4, green: 0.75, blue: 1)
        let m = kind.mouth
        // Eyes: open ones look toward the pointer; a panicked one can't keep still.
        func eyes(height: CGFloat = 2, pupils: Bool = true, jitter: CGFloat = 0) {
            for e in kind.eyes {
                dot(e.x, e.y + (2 - height), kind.socket, w: 2, h: height)
                if pupils {
                    let px = e.x + 0.5 + look.x * 0.5 + jitter, py = e.y + (2 - height) + max(0, height - 1) / 2 + look.y * min(0.5, (height - 1) / 2)
                    dot(px, py, kind.pupil)
                }
            }
        }
        func closed() { for e in kind.eyes { dot(e.x, e.y + 1.3, kind.socket, w: 2, h: 0.5) } }
        switch mood {
        case .sleepy:
            closed()
            let rise = CGFloat(frame % 24) / 8
            g.draw(Text("z").font(.system(size: 6, weight: .heavy)).foregroundColor(.white.opacity(0.8)),
                   at: CGPoint(x: (15 + dx) * p, y: (3 - rise) * p))
        case .panic:
            eyes(jitter: frame % 2 == 0 ? -0.2 : 0.2)
            dot(m.x - 1, m.y + 0.5, kind.shade, w: 2)
            dot(12, 1 + CGFloat(frame % 6) / 3, water, h: 1.5)
        case .eating:
            eyes(height: 1.5)
            dot(m.x - 1.25, m.y, kind.shade, w: 2.5, h: frame % 4 < 2 ? 1.5 : 0.5)
            if frame % 4 < 2 { dot(-1, 7, .white.opacity(0.7), w: 0.7, h: 0.7) }
        case .surprised:
            eyes()
            dot(m.x - 0.75, m.y, kind.shade, w: 1.5, h: 1.5)
            dot(13, 0.5, .white, h: 2.5); dot(13, 3.5, .white)
        case .late:
            eyes(height: 1)
            dot(m.x - 1, m.y - 0.2, kind.shade, w: 2, h: frame % 32 < 12 ? 1.8 : 0.6)
        case .thirsty:
            eyes(height: 1.5)
            dot(m.x - 0.75, m.y, Color(red: 1, green: 0.45, blue: 0.5), w: 1.5, h: 1)
            dot(12.5, 2 + CGFloat(frame % 8) / 4, water, w: 1, h: 1.5)
        case .love:
            for e in kind.eyes { dot(e.x, e.y + 1, kind.socket, w: 2, h: 0.6) }
            if let left = kind.eyes.first, let right = kind.eyes.last, kind != .frog {
                dot(left.x - 1, left.y + 2.5, blush, w: 1.5); dot(right.x + 1.5, right.y + 2.5, blush, w: 1.5)
            }
            dot(m.x - 1, m.y, kind.shade, w: 2, h: 0.6)
            heart(at: CGPoint(x: 12, y: 3 - CGFloat(frame % 12) / 4))
        case .dizzy:
            // Eyes that spin, and a star going round the head.
            for e in kind.eyes {
                dot(e.x, e.y, kind.socket, w: 2, h: 2)
                let a = CGFloat(frame) * 0.8
                dot(e.x + 0.5 + cos(a) * 0.5, e.y + 0.5 + sin(a) * 0.5, kind.pupil)
            }
            dot(m.x - 1, m.y, kind.shade, w: 2, h: 0.6)
            let a = CGFloat(frame) * 0.4
            dot(5.5 + cos(a) * 5, -1 + sin(a) * 0.8, Color(red: 1, green: 0.85, blue: 0.3))
        case .sad:
            eyes(height: 1)
            dot(m.x - 1, m.y + 0.6, kind.shade, w: 2, h: 0.5)
            dot(m.x - 1.4, m.y, kind.shade, w: 0.6, h: 0.6); dot(m.x + 0.8, m.y, kind.shade, w: 0.6, h: 0.6)
            if let e = kind.eyes.first { dot(e.x + 0.5, e.y + 2 + CGFloat(frame % 12) / 3, water, w: 0.8, h: 1.2) }
        case .party:
            for e in kind.eyes { dot(e.x, e.y + 0.5, kind.socket, w: 2, h: 0.6); dot(e.x + 0.5, e.y, kind.socket, w: 1, h: 0.6) }
            dot(m.x - 1.25, m.y - 0.3, kind.shade, w: 2.5, h: 1.4)
            let colors: [Color] = [.pink, .yellow, .cyan, .green, .orange]
            for i in 0..<5 {
                let x = CGFloat((i * 37 + frame) % 16) - 2, y = CGFloat((i * 13 + frame * 2) % 14) - 2
                dot(x, y, colors[i], w: 0.8, h: 0.8)
            }
        case .focus:
            eyes(height: 1.5)
            dot(m.x - 0.5, m.y, kind.shade, w: 1, h: 0.6)
        case .coffee:
            eyes(height: 1)
            dot(m.x - 1, m.y, kind.shade, w: 2, h: 0.6)
            // A little cup, steaming, beside it.
            dot(11.8, 6, .white, w: 2, h: 2); dot(13.8, 6.5, .white, w: 0.6, h: 1)
            dot(12.3 + CGFloat(frame % 8 < 4 ? 0 : 0.5), 4.5 - CGFloat(frame % 8) / 8, .white.opacity(0.5), w: 0.6, h: 1)
        case .tired:
            eyes(height: 0.8)
            dot(m.x - 0.75, m.y, kind.shade, w: 1.5, h: 0.5)
            // An empty battery beside it.
            dot(11.8, 3, Theme.red, w: 2.6, h: 0.4); dot(11.8, 4.6, Theme.red, w: 2.6, h: 0.4)
            dot(11.8, 3, Theme.red, w: 0.4, h: 2); dot(14, 3, Theme.red, w: 0.4, h: 2); dot(14.4, 3.6, Theme.red, w: 0.4, h: 0.8)
            dot(12.2, 3.4, Theme.red, w: 0.6, h: 1.2)
        case .charged:
            eyes()
            dot(m.x - 1, m.y, kind.shade, w: 2, h: 0.8)
            if frame % 4 < 3 {
                let bolt = Color(red: 1, green: 0.85, blue: 0.2)
                dot(14, 0.5, bolt, w: 1, h: 2); dot(13, 2.5, bolt, w: 2, h: 0.8); dot(13, 3.3, bolt, w: 1, h: 2)
            }
        case .hungry:
            eyes()
            dot(m.x - 0.75, m.y - 0.2, kind.shade, w: 1.5, h: 1.2)
            // An empty bowl, so a click feeds it.
            let bowl = Color(white: 0.85)
            dot(11.5, 8, bowl, w: 3, h: 0.6); dot(12, 8.6, bowl, w: 2, h: 0.6)
            if frame % 16 < 8 {
                g.draw(Text("?").font(.system(size: 6, weight: .heavy)).foregroundColor(.white.opacity(0.85)),
                       at: CGPoint(x: (15 + dx) * p, y: 4 * p))
            }
        case .happy, .dancing, .walking, .sway:
            if let left = kind.eyes.first, let right = kind.eyes.last, kind != .frog {
                dot(left.x - 1, left.y + 2.5, blush, w: 1.5); dot(right.x + 1.5, right.y + 2.5, blush, w: 1.5)
            }
            if frame % 40 == 0 { closed() } else { eyes() }
            if kind == .cat { dot(m.x - 0.5, m.y - 1, kind.shade) }
            dot(m.x - (kind == .frog ? 2 : 1), m.y, kind.shade, w: kind == .frog ? 4 : 2, h: 0.6)
            if mood == .dancing {
                let up = CGFloat(frame % 16) / 4
                g.draw(Text("♪").font(.system(size: 7, weight: .bold)).foregroundColor(.white.opacity(0.85)),
                       at: CGPoint(x: (14.5 + dx) * p, y: (6 - up) * p))
            }
        }
        wear(dot)
    }

    // What it has on: the cap for prayer or the focus headband first, else the chosen accessory.
    private func wear(_ dot: (CGFloat, CGFloat, Color, CGFloat, CGFloat) -> Void) {
        let top: CGFloat = kind == .cat ? 2 : 0
        if praying {
            let cap = Color(white: 0.12), band = Color(white: 0.3)
            dot(3, top - 1.5, cap, 6, 1); dot(2.5, top - 0.5, cap, 7, 0.8); dot(2.5, top - 0.5, band, 7, 0.3)
            return
        }
        if mood == .focus {
            let band = Theme.red
            dot(0.5, 1.5, band, 11, 0.8); dot(11.3, 1.8, band, 1.2, 0.6); dot(12, 2.4, band, 0.8, 0.6)
            return
        }
        switch accessory {
        case .none: break
        case .scarf:
            let red = Color(red: 0.9, green: 0.25, blue: 0.3)
            dot(1.5, 7.2, red, 9, 1); dot(8.5, 8.2, red, 1.2, 1.4)
        case .glasses:
            let frame = Color(white: 0.05)
            for e in kind.eyes {
                dot(e.x - 0.4, e.y - 0.4, frame, 2.8, 0.4); dot(e.x - 0.4, e.y + 2, frame, 2.8, 0.4)
                dot(e.x - 0.4, e.y - 0.4, frame, 0.4, 2.8); dot(e.x + 2, e.y - 0.4, frame, 0.4, 2.8)
            }
            if let l = kind.eyes.first, let r = kind.eyes.last { dot(l.x + 2.4, l.y + 0.4, frame, r.x - l.x - 2.4, 0.4) }
        case .cap:
            dot(3, top - 1.6, Theme.accent, 6, 1.2); dot(2, top - 0.5, Theme.accent, 8, 0.8); dot(9.5, top - 0.2, Theme.accent, 2.5, 0.5)
        case .crown:
            let gold = Color(red: 1, green: 0.8, blue: 0.25)
            dot(3, top - 0.9, gold, 6, 1); dot(3, top - 2, gold, 1, 1.2); dot(5.5, top - 2.2, gold, 1, 1.4); dot(8, top - 2, gold, 1, 1.2)
        }
    }
}
