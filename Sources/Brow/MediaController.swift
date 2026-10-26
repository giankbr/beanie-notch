import AppKit
import SwiftUI

struct NowPlaying: Equatable {
    var app: String
    var playing: Bool
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var elapsed: Double
    var timestamp: Double

    func position(at date: Date = Date()) -> Double {
        let p = elapsed + (playing ? date.timeIntervalSince1970 - timestamp : 0)
        return duration > 0 ? min(max(p, 0), duration) : max(p, 0)
    }
}

// Reads the system's Now Playing, so any player counts: Spotify, Music, YouTube in a browser, podcasts.
// macOS only lets Apple-signed processes read it, so Helper/NowPlaying.m runs inside /usr/bin/perl and
// streams one JSON line per change.
@MainActor
final class MediaController: ObservableObject {
    @Published var now: NowPlaying?
    @Published var artwork: NSImage? {
        didSet { tint = artwork.flatMap(Self.tint).map { Color(nsColor: $0) } }
    }
    // A color taken from the artwork, for the player's glow and buttons.
    @Published private(set) var tint: Color?
    @Published var volume: Double = 50
    @Published private(set) var sleepAt: Date?
    let lyrics = Lyrics()
    var onTrackChange: ((NowPlaying) -> Void)?
    private var sleepTimer: Timer?

    private var helper: Process?
    private var keepAlive: Pipe?
    private var buffer = Data()
    private var restarts = 0
    private let queue = DispatchQueue(label: "brow.media", qos: .utility)

    private static var library: String? {
        Bundle.main.privateFrameworksURL?.appendingPathComponent("libNowPlaying.dylib").path
    }

    private static func perl(_ symbol: String) -> String {
        "use DynaLoader; my $l = DynaLoader::dl_load_file($ARGV[0], 0) or exit 1; "
            + "my $s = DynaLoader::dl_find_symbol($l, '\(symbol)') or exit 1; "
            + "DynaLoader::dl_install_xsub('main::run', $s); run();"
    }

    init() {
        start()
        refreshVolume()
    }

    func setActive(_ active: Bool) {
        if active { refreshVolume() }
    }

    private func start() {
        guard let lib = Self.library, FileManager.default.fileExists(atPath: lib) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.perl("brow_stream"), lib]
        let output = Pipe(), input = Pipe()
        process.standardOutput = output
        // The helper exits when this pipe closes, which happens when Brow quits for any reason.
        process.standardInput = input
        process.standardError = FileHandle.nullDevice
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            Task { @MainActor in self?.receive(data) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in self?.helperExited() }
        }
        guard (try? process.run()) != nil else { return }
        helper = process
        keepAlive = input
    }

    private func helperExited() {
        helper = nil
        keepAlive = nil
        guard restarts < 3 else { return }
        restarts += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            MainActor.assumeIsolated { self?.start() }
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            apply(json)
        }
    }

    private func apply(_ json: [String: Any]) {
        if json["empty"] != nil {
            now = nil
            artwork = nil
            lyrics.clear()
            return
        }
        let next = NowPlaying(
            app: json["app"] as? String ?? "",
            playing: json["playing"] as? Bool ?? false,
            title: json["title"] as? String ?? "",
            artist: json["artist"] as? String ?? "",
            album: json["album"] as? String ?? "",
            duration: json["duration"] as? Double ?? 0,
            elapsed: json["elapsed"] as? Double ?? 0,
            timestamp: json["timestamp"] as? Double ?? Date().timeIntervalSince1970
        )
        if next.title != now?.title || next.artist != now?.artist {
            artwork = nil
            if next.playing, !next.title.isEmpty { onTrackChange?(next) }
        }
        if let encoded = json["artwork"] as? String, let data = Data(base64Encoded: encoded) {
            artwork = NSImage(data: data)
        }
        if next != now { now = next }
        lyrics.load(title: next.title, artist: next.artist, duration: next.duration)
    }

    func playPause() {
        if var n = now {
            n.elapsed = n.position()
            n.timestamp = Date().timeIntervalSince1970
            n.playing.toggle()
            now = n
        }
        send("2")
    }

    func next() { send("4") }
    func previous() { send("5") }
    func seek(_ t: Double) { send("seek:\(t)") }

    func skip(_ seconds: Double) {
        guard let n = now else { return }
        let target = max(0, n.position() + seconds)
        seek(n.duration > 0 ? min(target, n.duration - 1) : target)
    }

    // Pauses whatever is playing once the time is up; nil turns it off.
    func setSleep(minutes: Int?) {
        sleepTimer?.invalidate()
        sleepTimer = nil
        guard let minutes else {
            sleepAt = nil
            return
        }
        let end = Date().addingTimeInterval(Double(minutes * 60))
        sleepAt = end
        let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.send("1")
                self?.sleepAt = nil
            }
        }
        t.tolerance = 2
        RunLoop.main.add(t, forMode: .common)
        sleepTimer = t
    }

    // The average of the artwork's most colorful pixels, evened out so it reads on black and on white.
    nonisolated private static func tint(of image: NSImage) -> NSColor? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 16
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return nil }
        var samples: [(score: CGFloat, color: NSColor)] = []
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let c = NSColor(srgbRed: CGFloat(pixels[i]) / 255, green: CGFloat(pixels[i + 1]) / 255,
                            blue: CGFloat(pixels[i + 2]) / 255, alpha: 1)
            var s: CGFloat = 0, b: CGFloat = 0
            c.getHue(nil, saturation: &s, brightness: &b, alpha: nil)
            samples.append((s * b, c))
        }
        let top = samples.sorted { $0.score > $1.score }.prefix(samples.count / 4)
        guard !top.isEmpty else { return nil }
        var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0
        for sample in top {
            r += sample.color.redComponent; g += sample.color.greenComponent; bl += sample.color.blueComponent
        }
        let n = CGFloat(top.count)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0
        NSColor(srgbRed: r / n, green: g / n, blue: bl / n, alpha: 1).getHue(&h, saturation: &s, brightness: &b, alpha: nil)
        return NSColor(hue: h, saturation: min(max(s, 0.25), 0.7), brightness: 0.88, alpha: 1)
    }

    // MediaRemote command numbers: 1 pauses, 2 toggles play/pause, 4 is next track, 5 previous.
    private func send(_ command: String) {
        guard let lib = Self.library else { return }
        let script = Self.perl("brow_send")
        queue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = ["-e", script, lib]
            process.environment = ["BROW_CMD": command]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
        }
    }

    private func refreshVolume() {
        queue.async {
            let value = Self.script("output volume of (get volume settings)")?.int32Value
            Task { @MainActor in if let value { self.volume = Double(value) } }
        }
    }

    func setVolume(_ v: Double) {
        volume = v
        queue.async { _ = Self.script("set volume output volume \(Int(v))") }
    }

    nonisolated private static func script(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        return error == nil ? result : nil
    }
}
