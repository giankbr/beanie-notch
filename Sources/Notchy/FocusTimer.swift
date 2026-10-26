import Foundation

@MainActor
final class FocusTimer: ObservableObject {
    enum Phase { case focus, rest }

    static let presets: [(focus: Int, rest: Int)] = [(25, 5), (50, 10), (15, 3)]

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var preset = 0
    @Published private(set) var endDate: Date?
    @Published private(set) var remaining: TimeInterval = 25 * 60
    var onDone: ((Phase) -> Void)?
    private var alarm: Timer?

    var isRunning: Bool { endDate != nil }

    var duration: TimeInterval {
        let p = Self.presets[preset]
        return Double((phase == .focus ? p.focus : p.rest) * 60)
    }

    func left(at date: Date = Date()) -> TimeInterval {
        endDate.map { max(0, $0.timeIntervalSince(date)) } ?? remaining
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard endDate == nil else { return }
        let end = Date().addingTimeInterval(remaining)
        endDate = end
        // One timer at the end instead of a tick every second; the views count down on their own.
        let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.finish(notify: true) }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        alarm = t
    }

    func pause() {
        remaining = left()
        endDate = nil
        alarm?.invalidate()
    }

    func reset() {
        pause()
        remaining = duration
    }

    func choose(_ index: Int) {
        preset = index
        phase = .focus
        reset()
    }

    func skip() { finish(notify: false) }

    private func finish(notify: Bool) {
        let done = phase
        alarm?.invalidate()
        endDate = nil
        phase = phase == .focus ? .rest : .focus
        remaining = duration
        if notify { onDone?(done) }
    }
}
