import AppKit
import SwiftUI

// A coffee bean that lives in the right corner of the closed notch, whatever else shows there, and reacts to the Mac:
// it dozes when nobody's there, sweats when the processor is flat out, munches files put on the Shelf, wants water
// when it's time to drink, bobs along to music, jumps at each alert and yawns when you're up past midnight.
@MainActor
final class NotchPet: ObservableObject {
    enum Mood: Equatable { case happy, sleepy, panic, eating, thirsty, dancing, surprised, late }

    // The room it takes beside the notch's content, in points.
    static let slot: CGFloat = 38

    @Published private(set) var mood: Mood = .happy
    var stats: SystemStats?
    var playing: (() -> Bool)?
    private var timer: Timer?
    private var fedUntil = Date.distantPast
    private var thirstyUntil = Date.distantPast
    private var surprisedUntil = Date.distantPast

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
        update()
    }

    func feed() {
        fedUntil = Date().addingTimeInterval(4)
        update()
    }

    func surprise() {
        guard timer != nil else { return }
        surprisedUntil = Date().addingTimeInterval(2.5)
        update()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func thirst() {
        thirstyUntil = Date().addingTimeInterval(60)
        update()
    }

    private func update() {
        let now = Date()
        stats?.refresh()
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let hour = Calendar.current.component(.hour, from: now)
        let next: Mood = now < surprisedUntil ? .surprised
            : now < fedUntil ? .eating
            : (stats?.cpu ?? 0) > 0.85 ? .panic
            : now < thirstyUntil ? .thirsty
            : idle > 180 ? .sleepy
            : playing?() == true ? .dancing
            : hour < 4 ? .late
            : .happy
        if next != mood { mood = next }
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
        case .sleepy: dy = frame % 32 < 16 ? 2 : 2.5
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
        case .happy, .dancing:
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
    }
}
