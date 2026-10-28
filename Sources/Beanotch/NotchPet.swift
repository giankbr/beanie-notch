import AppKit
import SwiftUI

// A coffee bean that lives in the left corner of the closed notch, whatever else shows there, and reacts to the Mac:
// it dozes when nobody's there, sweats when the processor is flat out, munches files put on the Shelf, wants water
// when it's time to drink, bobs along to music, jumps at each alert and yawns when you're up past midnight.
@MainActor
final class NotchPet: ObservableObject {
    enum Mood: Equatable {
        case happy, sleepy, panic, eating, thirsty, dancing, surprised, late
        case love, dizzy, sad, party, focus, coffee, tired, charged, hungry, sway, walking
        // A twirl at a double click, a wave when you're back at the Mac, a game with its ball, a jig at a new song.
        case spin, wave, ball, groove
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
    private var away = false
    private var loads: [Double] = []
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
        } else if taps.count == 2, now.timeIntervalSince(taps[0]) < 0.45 {
            react(.spin, for: 0.9)
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

    // A new song: a little jig.
    func songChanged() { react(.groove, for: 2.2) }

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

    // Now and then, with nothing else going on, it walks from its corner on the left to the other end and back.
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
        // The load over the last quarter minute: a moment's spike (an app opening, a page loading) isn't running hot.
        loads = (loads + [stats?.cpu ?? 0]).suffix(5)
        let busy = loads.count == 5 && loads.reduce(0, +) / 5 > 0.9
        var next: Mood = reaction?.mood
            ?? (busy ? .panic
            : power.map { $0.percent < 20 && !$0.plugged } == true ? .tired
            : phase == .focus ? .focus
            : phase == .rest ? .coffee
            : idle > 180 ? .sleepy
            : playing?() == true ? .dancing
            : hour >= 10 && fedDay != Self.today ? .hungry
            : hour < 4 ? .late
            : .happy)
        if walk > 0 && next == .happy { next = .walking }
        // Back after being away five minutes: a wave hello.
        if idle > 300 { away = true } else if away, idle < 5 { away = false; react(.wave, for: 2.6); return }
        if next != mood { mood = next }
        if next == .happy, idle < 60, Int.random(in: 0..<60) == 0 { stroll() }
        // Left to itself for a bit (you're reading, say), it now and then plays with its ball.
        else if next == .happy, idle > 15, idle < 150, Int.random(in: 0..<40) == 0 { react(.ball, for: 5) }
    }
}

// Things to wear, unlocked by level; the cap for prayer and the focus headband come on by themselves.
enum PetAccessory: String, CaseIterable, Identifiable {
    case none, scarf, glasses, cap, sunglasses, crown, headphones, bow, santa
    var id: String { rawValue }
    var title: String { self == .none ? "Nothing" : rawValue.capitalized }
    var level: Int {
        switch self {
        case .none: 1
        case .scarf: 2
        case .glasses: 3
        case .cap: 4
        case .sunglasses: 5
        case .crown: 6
        case .headphones: 7
        case .bow: 8
        case .santa: 9
        }
    }
}

// The pets to pick from. Each is drawn on a 12 × 10 grid (where its eyes and mouth sit), its body at twice that
// detail from a few simple shapes, lit from the top left: a highlight along the lit edge, a shade along the other.
enum PetKind: String, CaseIterable, Identifiable {
    case bean, cat, frog, ghost, dog, panda, bunny, robot
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    enum Cell { case body, shade, light, accent, dark }

    // The body as cells at half a grid square, rows from the top (y −2 to 10) and columns 0 to 12.
    var cells: [[Cell?]] {
        if let known = PetKind.cache[self] { return known }
        var grid: [[Cell?]] = []
        for row in 0..<24 {
            var line: [Cell?] = []
            for col in 0..<24 {
                let x = (CGFloat(col) + 0.5) / 2, y = (CGFloat(row) + 0.5) / 2 - 2
                line.append(cell(x, y))
            }
            grid.append(line)
        }
        PetKind.cache[self] = grid
        return grid
    }
    nonisolated(unsafe) private static var cache: [PetKind: [[Cell?]]] = [:]

    private func ellipse(_ x: CGFloat, _ y: CGFloat, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Bool {
        pow((x - cx) / rx, 2) + pow((y - cy) / ry, 2) <= 1
    }

    // Whether a point is on the pet at all.
    private func inside(_ x: CGFloat, _ y: CGFloat) -> Bool {
        switch self {
        case .bean: return ellipse(x, y, 6, 5, 6, 5)
        case .cat:
            let ear = { (tip: CGFloat) in y >= 0 && y <= 3 && abs(x - tip) <= (y / 3) * 1.9 }
            return ellipse(x, y, 6, 6.2, 6, 4.2) || ear(1.6) || ear(10.4)
        case .frog: return ellipse(x, y, 6, 5.8, 6, 4.2) || ellipse(x, y, 2.6, 1.8, 1.9, 1.7) || ellipse(x, y, 9.4, 1.8, 1.9, 1.7)
        case .ghost:
            let wave = 9 + 0.7 * sin(x * .pi / 1.5)
            return (ellipse(x, y, 6, 5, 5.1, 5) && y <= 5) || (x >= 0.9 && x <= 11.1 && y > 5 && y <= wave)
        case .dog: return ellipse(x, y, 6, 5.6, 5.4, 4.5) || ellipse(x, y, 1, 4, 1.3, 2.8) || ellipse(x, y, 11, 4, 1.3, 2.8)
        case .panda: return ellipse(x, y, 6, 5.6, 5.8, 4.6) || ellipse(x, y, 1.8, 1.6, 1.5, 1.4) || ellipse(x, y, 10.2, 1.6, 1.5, 1.4)
        case .bunny:
            let ear = { (cx: CGFloat) in ellipse(x, y, cx, 0.4, 0.95, 2.6) }
            return ellipse(x, y, 6, 6.2, 5.4, 4) || ear(3.6) || ear(8.4)
        case .robot:
            let box = x >= 1 && x <= 11 && y >= 1.4 && y <= 9.6
            let corner = [(2.2, 2.6), (9.8, 2.6), (2.2, 8.4), (9.8, 8.4)].contains { (cx, cy) in
                (x < 2.2 || x > 9.8) && (y < 2.6 || y > 8.4) && hypot(x - cx, y - cy) > 1.2 && abs(x - cx) < 1.3 && abs(y - cy) < 1.3
            }
            let antenna = abs(x - 6) < 0.3 && y > -0.6 && y < 1.4
            return (box && !corner) || antenna || ellipse(x, y, 6, -0.9, 0.7, 0.7)
        }
    }

    // Parts in their own colour: a cat's and a bunny's inner ears, a dog's ears and snout, a panda's ears and eye
    // patches, the bean's crease, a robot's screen and antenna tip.
    private func detail(_ x: CGFloat, _ y: CGFloat) -> Cell? {
        switch self {
        case .bean: return abs(x - (8.4 - (y - 6.2) * 0.75)) < 0.45 && y > 5.8 ? .shade : nil
        case .cat:
            let inner = { (tip: CGFloat) in y >= 1 && y <= 2.9 && abs(x - tip) <= ((y - 1) / 2) * 0.9 }
            return inner(1.6) || inner(10.4) ? .accent : nil
        case .dog:
            if ellipse(x, y, 1, 4, 1.3, 2.8) || ellipse(x, y, 11, 4, 1.3, 2.8) { return .dark }
            return ellipse(x, y, 6, 6.8, 2.2, 1.5) ? .accent : nil
        case .panda:
            if ellipse(x, y, 1.8, 1.6, 1.5, 1.4) || ellipse(x, y, 10.2, 1.6, 1.5, 1.4) { return .dark }
            return ellipse(x, y, 3.5, 4.3, 1.7, 1.5) || ellipse(x, y, 8.5, 4.3, 1.7, 1.5) ? .dark : nil
        case .bunny: return ellipse(x, y, 3.6, 0.6, 0.45, 2) || ellipse(x, y, 8.4, 0.6, 0.45, 2) ? .accent : nil
        case .robot:
            if ellipse(x, y, 6, -0.9, 0.7, 0.7) { return .accent }
            return x >= 2.2 && x <= 9.8 && y >= 2.8 && y <= 7.8 ? .dark : nil
        case .frog: return ellipse(x, y, 6, 7.2, 3.8, 1.8) ? .light : nil
        case .ghost: return nil
        }
    }

    private func cell(_ x: CGFloat, _ y: CGFloat) -> Cell? {
        guard inside(x, y) else { return nil }
        if let d = detail(x, y) { return d }
        // Lit from the top left: the edge facing the light is brighter, the far edge darker.
        let lit = !inside(x - 0.7, y - 0.7), dark = !inside(x + 0.8, y + 0.8) || !inside(x, y + 0.9)
        if dark { return .shade }
        if lit { return .light }
        return .body
    }

    var body: Color {
        switch self {
        case .bean: Color(red: 0.62, green: 0.4, blue: 0.26)
        case .cat: Color(red: 0.96, green: 0.6, blue: 0.26)
        case .frog: Color(red: 0.42, green: 0.76, blue: 0.36)
        case .ghost: Color(red: 0.92, green: 0.92, blue: 1)
        case .dog: Color(red: 0.86, green: 0.68, blue: 0.46)
        case .panda: Color(red: 0.96, green: 0.96, blue: 0.95)
        case .bunny: Color(red: 0.95, green: 0.9, blue: 0.92)
        case .robot: Color(red: 0.66, green: 0.72, blue: 0.8)
        }
    }

    var shade: Color {
        switch self {
        case .bean: Color(red: 0.36, green: 0.22, blue: 0.14)
        case .cat: Color(red: 0.74, green: 0.38, blue: 0.14)
        case .frog: Color(red: 0.2, green: 0.48, blue: 0.2)
        case .ghost: Color(red: 0.62, green: 0.6, blue: 0.78)
        case .dog: Color(red: 0.62, green: 0.44, blue: 0.26)
        case .panda: Color(red: 0.72, green: 0.72, blue: 0.74)
        case .bunny: Color(red: 0.74, green: 0.66, blue: 0.72)
        case .robot: Color(red: 0.4, green: 0.45, blue: 0.54)
        }
    }

    var light: Color {
        switch self {
        case .frog: Color(red: 0.7, green: 0.9, blue: 0.56)
        case .ghost, .panda, .bunny: .white
        default: body.mix(.white, 0.32)
        }
    }

    var accent: Color {
        switch self {
        case .cat, .bunny: Color(red: 1, green: 0.62, blue: 0.68)
        case .dog: Color(red: 0.96, green: 0.86, blue: 0.72)
        case .robot: Color(red: 1, green: 0.36, blue: 0.38)
        default: shade
        }
    }

    var dark: Color {
        switch self {
        case .dog: Color(red: 0.45, green: 0.3, blue: 0.18)
        case .panda: Color(red: 0.14, green: 0.14, blue: 0.16)
        case .robot: Color(red: 0.12, green: 0.15, blue: 0.2)
        default: shade
        }
    }

    // The white of the eye and the pupil; the ghost's are the other way round, the robot's glow on its screen.
    var socket: Color {
        switch self {
        case .ghost: Color(red: 0.16, green: 0.15, blue: 0.26)
        case .robot: Color(red: 0.36, green: 0.92, blue: 1)
        default: .white
        }
    }
    var pupil: Color {
        switch self {
        case .ghost: .white
        case .robot: Color(red: 0.08, green: 0.5, blue: 0.62)
        default: Color(red: 0.12, green: 0.08, blue: 0.06)
        }
    }
    // The mouth: drawn in the shade, or lit on the robot's screen, or dark on the white ones.
    var ink: Color {
        switch self {
        case .robot: socket
        case .panda, .bunny, .ghost: Color(red: 0.3, green: 0.26, blue: 0.32)
        default: shade
        }
    }

    // Each eye's top-left square, and the middle of the mouth.
    var eyes: [CGPoint] {
        switch self {
        case .frog: [CGPoint(x: 1.6, y: 0.8), CGPoint(x: 8.4, y: 0.8)]
        case .cat: [CGPoint(x: 2.5, y: 3.8), CGPoint(x: 7.5, y: 3.8)]
        case .bunny: [CGPoint(x: 2.8, y: 4.2), CGPoint(x: 7.2, y: 4.2)]
        case .robot: [CGPoint(x: 3.2, y: 3.8), CGPoint(x: 6.8, y: 3.8)]
        case .panda: [CGPoint(x: 2.6, y: 3.4), CGPoint(x: 7.4, y: 3.4)]
        default: [CGPoint(x: 2.5, y: 3), CGPoint(x: 7.5, y: 3)]
        }
    }

    var mouth: CGPoint {
        switch self {
        case .frog: CGPoint(x: 6, y: 5)
        case .cat: CGPoint(x: 6, y: 6.6)
        case .dog: CGPoint(x: 6, y: 7.3)
        case .bunny: CGPoint(x: 6, y: 7.1)
        case .robot: CGPoint(x: 6, y: 6.5)
        case .panda: CGPoint(x: 6, y: 7)
        default: CGPoint(x: 6, y: 6.5)
        }
    }

    // A dark nose for the ones that have one.
    var nose: CGPoint? {
        switch self {
        case .dog: CGPoint(x: 6, y: 6.1)
        case .cat, .bunny: CGPoint(x: 6, y: 6)
        case .panda: CGPoint(x: 6, y: 6.1)
        default: nil
        }
    }
}

extension Color {
    // Part way toward another colour, worked out in sRGB.
    func mix(_ other: Color, _ amount: CGFloat) -> Color {
        let a = NSColor(self).usingColorSpace(.sRGB) ?? .gray, b = NSColor(other).usingColorSpace(.sRGB) ?? .gray
        return Color(red: a.redComponent + (b.redComponent - a.redComponent) * amount,
                     green: a.greenComponent + (b.greenComponent - a.greenComponent) * amount,
                     blue: a.blueComponent + (b.blueComponent - a.blueComponent) * amount)
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
        // Thirty frames a second for smooth motion; the pixels themselves stay on their grid.
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let look = look()
            Canvas { g, size in draw(&g, size: size, t: t, look: look) }
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

    // A steady pseudo-random number in 0…1 for a whole number, so idle habits differ from one stretch to the next.
    private static func chance(_ n: Int) -> Double {
        var x = UInt64(bitPattern: Int64(n)) &* 0x9E3779B97F4A7C15
        x ^= x >> 29; x = x &* 0xBF58476D1CE4E5B9; x ^= x >> 32
        return Double(x % 10_000) / 10_000
    }

    private func draw(_ g: inout GraphicsContext, size: CGSize, t: Double, look given: CGPoint) {
        let p = Self.pixel
        let frame = Int(t * 8)
        // Idle habits, a few seconds out of every ten while it's content: a look around, a yawn, a wiggle, a twitch.
        let stretch = Int(t / 10), into = t.truncatingRemainder(dividingBy: 10)
        let habit = mood == .happy && into < 2.4 ? Int(Self.chance(stretch) * 5) : -1
        var look = given
        if habit == 0 { look = CGPoint(x: sin(into / 2.4 * .pi * 2) * 0.9, y: 0) }
        let yawning = habit == 1 && into > 0.3 && into < 2

        // Moves, now continuous: a bob to music, a hop at an alert, a shake when panicking, slow breathing otherwise.
        var dx: CGFloat = 0, dy: CGFloat = 2
        switch mood {
        case .dancing, .groove: dy = 2 - abs(sin(t * .pi * 2.4)) * 1.2; dx = mood == .groove ? sin(t * .pi * 2.4) * 0.6 : 0
        case .surprised: dy = 2 - abs(sin(t * .pi * 3)) * 1.2
        case .panic: dx = sin(t * 60) * 0.5
        case .sleepy, .tired: dy = 2 + sin(t * 1.4) * 0.3
        case .love, .party, .charged, .wave: dy = 2 - abs(sin(t * .pi * 2)) * 1.1
        case .walking: dy = 2 - abs(sin(t * .pi * 4)) * 0.5
        case .sway: dx = sin(t * 7) * 1.2
        case .dizzy: dx = sin(t * 4) * 0.6
        case .ball: dy = 2 - abs(sin(t * .pi * 1.6)) * 0.6
        default: dy = 2 + sin(t * 1.8) * 0.18
        }
        if habit == 2 { dx = sin(into * 9) * 0.5 }
        // On the half-square grid, so the pixels stay crisp.
        dx = (dx * 2).rounded() / 2
        dy = (dy * 4).rounded() / 4

        // A twirl: the pet narrows to an edge and widens again, flipping as it turns.
        if mood == .spin {
            let turn = cos(t.truncatingRemainder(dividingBy: 0.9) / 0.9 * .pi * 2)
            g.translateBy(x: size.width / 2, y: 0)
            g.scaleBy(x: max(0.08, abs(turn)) * (turn < 0 ? -1 : 1), y: 1)
            g.translateBy(x: -size.width / 2, y: 0)
        }

        func dot(_ x: CGFloat, _ y: CGFloat, _ color: Color, w: CGFloat = 1, h: CGFloat = 1) {
            // A hair larger than the grid, so no seams show between pixels.
            g.fill(Path(CGRect(x: (x + 3 + dx) * p, y: (y + dy) * p, width: w * p + 0.3, height: h * p + 0.3)), with: .color(color))
        }
        // The body, cell by cell; a cat's, a dog's and a bunny's ears twitch now and then.
        let twitch = habit == 3 && Int(into * 6) % 2 == 0 ? CGFloat(-0.5) : 0
        for (row, line) in kind.cells.enumerated() {
            for (col, cell) in line.enumerated() {
                guard let cell else { continue }
                let x = CGFloat(col) / 2, y = CGFloat(row) / 2 - 2
                let ear = (kind == .cat || kind == .bunny) ? y < 2.6 : kind == .dog ? (x < 2.3 || x > 9.7) : false
                let color: Color = switch cell {
                case .body: kind.body
                case .shade: kind.shade
                case .light: kind.light
                case .accent: kind.accent
                case .dark: kind.dark
                }
                dot(x, y + (ear ? twitch : 0), color, w: 0.5, h: 0.5)
            }
        }
        // A glint high on the lit side.
        if kind != .ghost && kind != .robot { dot(kind == .frog ? 4.2 : 2.2, kind == .bunny ? 2.8 : 1.8, .white.opacity(0.45), w: 1, h: 0.5) }
        if let nose = kind.nose { dot(nose.x - 0.5, nose.y, kind == .panda || kind == .dog ? kind.dark : kind.accent, w: 1, h: 0.6) }
        func heart(at o: CGPoint) {
            let red = Color(red: 1, green: 0.35, blue: 0.45)
            dot(o.x, o.y, red); dot(o.x + 2, o.y, red); dot(o.x, o.y + 1, red, w: 3); dot(o.x + 1, o.y + 2, red)
        }

        let blush = Color(red: 1, green: 0.5, blue: 0.55).opacity(0.55)
        let water = Color(red: 0.4, green: 0.75, blue: 1)
        let m = kind.mouth
        // A blink every few seconds, sometimes two in a row.
        let cycle = 3.6 + Self.chance(Int(t / 3.6)) * 2.4
        let phase = t.truncatingRemainder(dividingBy: cycle)
        let blinking = phase < 0.12 || (Self.chance(Int(t / 3.6) + 7) > 0.7 && phase > 0.28 && phase < 0.4)
        // Eyes: open ones look toward the pointer; a panicked one can't keep still.
        func eyes(height: CGFloat = 2, pupils: Bool = true, jitter: CGFloat = 0) {
            if blinking || yawning { return closed() }
            for e in kind.eyes {
                dot(e.x, e.y + (2 - height), kind.socket, w: 2, h: height)
                if pupils {
                    let px = e.x + 0.5 + look.x * 0.5 + jitter, py = e.y + (2 - height) + max(0, height - 1) / 2 + look.y * min(0.5, (height - 1) / 2)
                    dot(px, py, kind.pupil)
                    // A spark of light in each pupil.
                    if height >= 2 && kind != .robot && kind != .panda { dot(px + 0.5, py, .white.opacity(0.85), w: 0.5, h: 0.5) }
                }
            }
        }
        func closed() { for e in kind.eyes { dot(e.x, e.y + 1.3, kind == .robot ? kind.socket : kind.ink, w: 2, h: 0.5) } }
        func cheeks() {
            guard kind != .frog, kind != .robot, let left = kind.eyes.first, let right = kind.eyes.last else { return }
            dot(left.x - 1, left.y + 2.5, blush, w: 1.5); dot(right.x + 1.5, right.y + 2.5, blush, w: 1.5)
        }
        func smile(_ wide: Bool = false) { dot(m.x - (wide ? 2 : 1), m.y, kind.ink, w: wide ? 4 : 2, h: 0.6) }
        switch mood {
        case .sleepy:
            closed()
            let rise = CGFloat(t.truncatingRemainder(dividingBy: 3)) / 3 * 3
            g.draw(Text("z").font(.system(size: 6, weight: .heavy)).foregroundColor(.white.opacity(0.8 - rise * 0.2)),
                   at: CGPoint(x: (15 + dx + rise * 0.3) * p, y: (3 - rise) * p))
        case .panic:
            eyes(jitter: sin(t * 40) * 0.2)
            dot(m.x - 1, m.y + 0.5, kind.ink, w: 2)
            dot(12, 1 + CGFloat(t.truncatingRemainder(dividingBy: 0.75)) * 2.6, water, h: 1.5)
        case .eating:
            eyes(height: 1.5)
            dot(m.x - 1.25, m.y, kind.ink, w: 2.5, h: 0.5 + abs(sin(t * 8)))
            if frame % 4 < 2 { dot(-1, 7, .white.opacity(0.7), w: 0.7, h: 0.7) }
        case .surprised:
            eyes()
            dot(m.x - 0.75, m.y, kind.ink, w: 1.5, h: 1.5)
            dot(13, 0.5, .white, h: 2.5); dot(13, 3.5, .white)
        case .late:
            eyes(height: 1)
            dot(m.x - 1, m.y - 0.2, kind.ink, w: 2, h: 0.6 + max(0, sin(t * 1.2)) * 1.2)
        case .thirsty:
            eyes(height: 1.5)
            dot(m.x - 0.75, m.y, Color(red: 1, green: 0.45, blue: 0.5), w: 1.5, h: 1)
            dot(12.5, 2 + CGFloat(t.truncatingRemainder(dividingBy: 1)) * 2, water, w: 1, h: 1.5)
        case .love:
            for e in kind.eyes { dot(e.x, e.y + 1, kind.socket, w: 2, h: 0.6) }
            cheeks()
            smile()
            heart(at: CGPoint(x: 12, y: 3 - CGFloat(t.truncatingRemainder(dividingBy: 1.5)) * 2))
        case .dizzy:
            // Eyes that spin, and a star going round the head.
            for e in kind.eyes {
                dot(e.x, e.y, kind.socket, w: 2, h: 2)
                dot(e.x + 0.5 + cos(t * 6.4) * 0.5, e.y + 0.5 + sin(t * 6.4) * 0.5, kind.pupil)
            }
            smile()
            dot(5.5 + cos(t * 3.2) * 5, -1 + sin(t * 3.2) * 0.8, Color(red: 1, green: 0.85, blue: 0.3))
        case .sad:
            eyes(height: 1)
            dot(m.x - 1, m.y + 0.6, kind.ink, w: 2, h: 0.5)
            dot(m.x - 1.4, m.y, kind.ink, w: 0.6, h: 0.6); dot(m.x + 0.8, m.y, kind.ink, w: 0.6, h: 0.6)
            if let e = kind.eyes.first { dot(e.x + 0.5, e.y + 2 + CGFloat(t.truncatingRemainder(dividingBy: 1.5)) * 2, water, w: 0.8, h: 1.2) }
        case .party, .groove:
            for e in kind.eyes { dot(e.x, e.y + 0.5, kind.socket, w: 2, h: 0.6); dot(e.x + 0.5, e.y, kind.socket, w: 1, h: 0.6) }
            dot(m.x - 1.25, m.y - 0.3, kind.ink, w: 2.5, h: 1.4)
            if mood == .party {
                let colors: [Color] = [.pink, .yellow, .cyan, .green, .orange]
                for i in 0..<5 {
                    let x = CGFloat((i * 37 + frame) % 16) - 2, y = CGFloat((i * 13 + frame * 2) % 14) - 2
                    dot(x, y, colors[i], w: 0.8, h: 0.8)
                }
            } else {
                let up = CGFloat(t.truncatingRemainder(dividingBy: 1.1)) * 3
                g.draw(Text("♪").font(.system(size: 7, weight: .bold)).foregroundColor(.white.opacity(0.9)), at: CGPoint(x: (14.5 + dx) * p, y: (6 - up) * p))
                g.draw(Text("♫").font(.system(size: 6, weight: .bold)).foregroundColor(.white.opacity(0.7)), at: CGPoint(x: (-1.5 + dx) * p, y: (5 - up * 0.8) * p))
            }
        case .focus:
            eyes(height: 1.5)
            dot(m.x - 0.5, m.y, kind.ink, w: 1, h: 0.6)
        case .coffee:
            eyes(height: 1)
            smile()
            // A little cup, steaming, beside it.
            dot(11.8, 6, .white, w: 2, h: 2); dot(13.8, 6.5, .white, w: 0.6, h: 1)
            let rise = CGFloat(t.truncatingRemainder(dividingBy: 1.2)) / 1.2
            dot(12.3 + sin(t * 4) * 0.3, 4.6 - rise * 1.6, .white.opacity(0.55 - rise * 0.4), w: 0.6, h: 1)
        case .tired:
            eyes(height: 0.8)
            dot(m.x - 0.75, m.y, kind.ink, w: 1.5, h: 0.5)
            // An empty battery beside it.
            dot(11.8, 3, Theme.red, w: 2.6, h: 0.4); dot(11.8, 4.6, Theme.red, w: 2.6, h: 0.4)
            dot(11.8, 3, Theme.red, w: 0.4, h: 2); dot(14, 3, Theme.red, w: 0.4, h: 2); dot(14.4, 3.6, Theme.red, w: 0.4, h: 0.8)
            dot(12.2, 3.4, Theme.red, w: 0.6, h: 1.2)
        case .charged:
            eyes()
            dot(m.x - 1, m.y, kind.ink, w: 2, h: 0.8)
            if frame % 4 < 3 {
                let bolt = Color(red: 1, green: 0.85, blue: 0.2)
                dot(14, 0.5, bolt, w: 1, h: 2); dot(13, 2.5, bolt, w: 2, h: 0.8); dot(13, 3.3, bolt, w: 1, h: 2)
            }
        case .hungry:
            eyes()
            dot(m.x - 0.75, m.y - 0.2, kind.ink, w: 1.5, h: 1.2)
            // An empty bowl, so a click feeds it.
            let bowl = Color(white: 0.85)
            dot(11.5, 8, bowl, w: 3, h: 0.6); dot(12, 8.6, bowl, w: 2, h: 0.6)
            if frame % 16 < 8 {
                g.draw(Text("?").font(.system(size: 6, weight: .heavy)).foregroundColor(.white.opacity(0.85)),
                       at: CGPoint(x: (15 + dx) * p, y: 4 * p))
            }
        case .wave:
            cheeks()
            eyes()
            smile(true)
            // A paw raised beside it, waving.
            let paw = sin(t * .pi * 4) * 0.8
            dot(12 + paw, 3, kind.body, w: 1.4, h: 1.4); dot(12.4 + paw, 4.4, kind.body, w: 0.8, h: 1.6)
        case .ball:
            // A ball beside it, bouncing; its eyes follow the ball.
            let hop = abs(sin(t * .pi * 1.6))
            let bx = 13.2 + sin(t * 1.1) * 0.8, by = 8.2 - hop * 4
            look = CGPoint(x: 0.9, y: by < 6 ? -0.6 : 0.4)
            cheeks()
            for e in kind.eyes where !blinking {
                dot(e.x, e.y, kind.socket, w: 2, h: 2)
                dot(e.x + 0.5 + look.x * 0.5, e.y + 0.5 + look.y * 0.5, kind.pupil)
            }
            if blinking { closed() }
            smile()
            let ball = Theme.accent
            dot(bx, by, ball, w: 1.6, h: 1.6); dot(bx + 0.3, by + 0.2, .white.opacity(0.6), w: 0.5, h: 0.5)
        case .spin:
            eyes()
            smile()
        case .happy, .dancing, .walking, .sway:
            cheeks()
            eyes()
            if kind == .cat { dot(m.x - 0.5, m.y - 1, kind.ink, w: 1, h: 0.5) }
            if yawning {
                let open = sin((into - 0.3) / 1.7 * .pi)
                dot(m.x - 0.8, m.y - 0.6, kind.dark == kind.shade ? Color(white: 0.12) : kind.dark, w: 1.6, h: 0.6 + open * 1.6)
            } else {
                smile(kind == .frog)
            }
            if mood == .dancing {
                let up = CGFloat(t.truncatingRemainder(dividingBy: 2)) / 2 * 4
                g.draw(Text("♪").font(.system(size: 7, weight: .bold)).foregroundColor(.white.opacity(0.85)),
                       at: CGPoint(x: (14.5 + dx) * p, y: (6 - up) * p))
            }
        }
        wear(dot)
    }

    // What it has on: the cap for prayer or the focus headband first, else the chosen accessory.
    private func wear(_ dot: (CGFloat, CGFloat, Color, CGFloat, CGFloat) -> Void) {
        let top: CGFloat = kind == .cat ? 2 : kind == .bunny ? 2.2 : kind == .robot ? 1.4 : 0
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
            dot(1.5, 7.6, red, 9, 1); dot(1.5, 7.6, red.mix(.white, 0.25), 9, 0.3); dot(8.5, 8.6, red, 1.2, 1.4)
        case .glasses:
            let rim = Color(white: 0.05)
            for e in kind.eyes {
                dot(e.x - 0.4, e.y - 0.4, rim, 2.8, 0.4); dot(e.x - 0.4, e.y + 2, rim, 2.8, 0.4)
                dot(e.x - 0.4, e.y - 0.4, rim, 0.4, 2.8); dot(e.x + 2, e.y - 0.4, rim, 0.4, 2.8)
            }
            if let l = kind.eyes.first, let r = kind.eyes.last { dot(l.x + 2.4, l.y + 0.4, rim, r.x - l.x - 2.4, 0.4) }
        case .sunglasses:
            let lens = Color(white: 0.06)
            for e in kind.eyes {
                dot(e.x - 0.4, e.y, lens, 2.8, 1.8)
                dot(e.x, e.y + 0.3, .white.opacity(0.35), 0.8, 0.4)
            }
            if let l = kind.eyes.first, let r = kind.eyes.last { dot(l.x + 2.4, l.y + 0.3, lens, r.x - l.x - 2.4, 0.5) }
        case .cap:
            dot(3, top - 1.6, Theme.accent, 6, 1.2); dot(2, top - 0.5, Theme.accent, 8, 0.8); dot(9.5, top - 0.2, Theme.accent, 2.5, 0.5)
        case .crown:
            let gold = Color(red: 1, green: 0.8, blue: 0.25)
            dot(3, top - 0.9, gold, 6, 1); dot(3, top - 2, gold, 1, 1.2); dot(5.5, top - 2.2, gold, 1, 1.4); dot(8, top - 2, gold, 1, 1.2)
            dot(5.7, top - 0.7, Color(red: 0.9, green: 0.2, blue: 0.3), 0.6, 0.6)
        case .headphones:
            let band = Color(white: 0.16), pad = Theme.accent
            dot(1, top - 1.2, band, 10, 0.6); dot(0.6, top - 0.8, band, 0.6, 3.5); dot(10.8, top - 0.8, band, 0.6, 3.5)
            dot(-0.2, top + 2.2, pad, 1.4, 2.4); dot(10.8, top + 2.2, pad, 1.4, 2.4)
        case .bow:
            let pink = Color(red: 1, green: 0.42, blue: 0.62)
            dot(7.6, top - 0.8, pink, 1.5, 1.4); dot(10, top - 0.8, pink, 1.5, 1.4); dot(9.1, top - 0.5, pink.mix(.black, 0.2), 0.9, 0.9)
        case .santa:
            let red = Color(red: 0.88, green: 0.18, blue: 0.22)
            dot(3, top - 1.6, red, 6, 1.4); dot(4.5, top - 2.6, red, 3.6, 1.2); dot(7.6, top - 2.4, red, 1.6, 0.8)
            dot(2.4, top - 0.4, .white, 7.2, 0.8); dot(9, top - 2.6, .white, 1.1, 1.1)
        }
    }
}
