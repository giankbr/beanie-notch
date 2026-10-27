import AppKit
import SwiftUI

// A coffee bean that lives in the closed notch and reacts to the Mac: it dozes when nobody's there, sweats when the
// processor is flat out, munches files put on the Shelf, wants water when it's time to drink, and bobs along to music.
@MainActor
final class NotchPet: ObservableObject {
    enum Mood: Equatable { case happy, sleepy, panic, eating, thirsty, dancing }

    @Published private(set) var mood: Mood = .happy
    var stats: SystemStats?
    var playing: (() -> Bool)?
    private var timer: Timer?
    private var fedUntil = Date.distantPast
    private var thirstyUntil = Date.distantPast

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

    func thirst() {
        thirstyUntil = Date().addingTimeInterval(60)
        update()
    }

    private func update() {
        let now = Date()
        stats?.refresh()
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
        let next: Mood = now < fedUntil ? .eating
            : (stats?.cpu ?? 0) > 0.85 ? .panic
            : now < thirstyUntil ? .thirsty
            : idle > 180 ? .sleepy
            : playing?() == true ? .dancing
            : .happy
        if next != mood { mood = next }
    }
}

struct PetView: View {
    let mood: NotchPet.Mood

    // The bean, a pixel to a character: body, and the end of its crease curling round the bottom.
    private static let shape = [
        "....####....",
        "..########..",
        ".##########.",
        ".##########.",
        "############",
        "############",
        "############",
        ".#######-##.",
        "..#####-##..",
        "....##-#....",
    ]
    private static let body = Color(red: 0.62, green: 0.4, blue: 0.26)
    private static let shade = Color(red: 0.36, green: 0.22, blue: 0.14)
    private static let pixel: CGFloat = 1.9

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.125)) { context in
            let frame = Int(context.date.timeIntervalSinceReferenceDate * 8)
            Canvas { g, _ in draw(&g, frame: frame) }
                .frame(width: 18 * Self.pixel, height: 14 * Self.pixel)
        }
    }

    private func draw(_ g: inout GraphicsContext, frame: Int) {
        let p = Self.pixel
        // Moves: a bob to music, a shake when panicking, slow breathing otherwise.
        var dx: CGFloat = 0, dy: CGFloat = 2
        switch mood {
        case .dancing: dy = frame % 4 < 2 ? 1 : 3
        case .panic: dx = frame % 2 == 0 ? -0.5 : 0.5
        case .sleepy: dy = frame % 32 < 16 ? 2 : 2.5
        default: dy = frame % 24 < 12 ? 2 : 2.3
        }
        func dot(_ x: CGFloat, _ y: CGFloat, _ color: Color, w: CGFloat = 1, h: CGFloat = 1) {
            // A hair larger than the grid, so no seams show between pixels.
            g.fill(Path(CGRect(x: (x + 3 + dx) * p, y: (y + dy) * p, width: w * p + 0.3, height: h * p + 0.3)), with: .color(color))
        }
        for (y, row) in Self.shape.enumerated() {
            for (x, c) in row.enumerated() where c != "." {
                dot(CGFloat(x), CGFloat(y), c == "-" ? Self.shade : Self.body)
            }
        }
        dot(2, 2, .white.opacity(0.35))

        // Eyes, and what the face is doing.
        let eye = Color.white
        let blink = frame % 40 == 0
        switch mood {
        case .sleepy:
            dot(2.5, 4.5, eye, w: 2, h: 0.5); dot(7.5, 4.5, eye, w: 2, h: 0.5)
            let rise = CGFloat(frame % 24) / 8
            g.draw(Text("z").font(.system(size: 6, weight: .heavy)).foregroundColor(.white.opacity(0.8)),
                   at: CGPoint(x: (15 + dx) * p, y: (3 - rise) * p))
        case .panic:
            dot(3, 3.5, eye, h: 2); dot(8, 3.5, eye, h: 2)
            dot(4.5, 7, Self.shade, w: 2)
            dot(12, 1 + CGFloat(frame % 6) / 3, Color(red: 0.4, green: 0.75, blue: 1), h: 1.5)
        case .eating:
            dot(3, 4, eye, h: 1.5); dot(8, 4, eye, h: 1.5)
            dot(4.5, 6.5, Self.shade, w: 2.5, h: frame % 4 < 2 ? 1.5 : 0.5)
            if frame % 4 < 2 { dot(-1, 7, .white.opacity(0.7), w: 0.7, h: 0.7) }
        case .thirsty:
            dot(3, 4, eye, h: 1.5); dot(8, 4, eye, h: 1.5)
            dot(5, 6.5, Color(red: 1, green: 0.45, blue: 0.5), w: 1.5, h: 1)
            dot(12.5, 2 + CGFloat(frame % 8) / 4, Color(red: 0.4, green: 0.75, blue: 1), w: 1, h: 1.5)
        case .happy, .dancing:
            dot(1.5, 5.5, Color(red: 1, green: 0.5, blue: 0.55).opacity(0.55), w: 1.5); dot(9, 5.5, Color(red: 1, green: 0.5, blue: 0.55).opacity(0.55), w: 1.5)
            if blink { dot(3, 4.5, eye, h: 0.5); dot(8, 4.5, eye, h: 0.5) } else { dot(3, 3.5, eye, h: 2); dot(8, 3.5, eye, h: 2) }
            dot(4.5, 6.5, Self.shade, w: 2, h: 0.6)
            if mood == .dancing {
                let up = CGFloat(frame % 16) / 4
                g.draw(Text("♪").font(.system(size: 7, weight: .bold)).foregroundColor(.white.opacity(0.85)),
                       at: CGPoint(x: (14.5 + dx) * p, y: (6 - up) * p))
            }
        }
    }
}
