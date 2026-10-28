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

    // What the system's Now Playing last said, and what Music or Spotify last said themselves. The system follows
    // one app at a time and can stay on a paused browser tab while Music plays; the players' own broadcasts need no
    // permission and say what they're doing, so whichever changed to playing most recently wins.
    private var system: (state: NowPlaying, at: Date)?
    private var player: (state: NowPlaying, at: Date)?
    // Commands go to the player straight when that's what's showing; MediaRemote only reaches the system's choice.
    private var direct: String?

    private var helper: Process?
    private var keepAlive: Pipe?
    private var buffer = Data()
    private var restarts = 0
    private let queue = DispatchQueue(label: "beanotch.media", qos: .utility)

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
        let center = DistributedNotificationCenter.default()
        for (name, app) in [("com.apple.Music.playerInfo", "Music"), ("com.spotify.client.PlaybackStateChanged", "Spotify")] {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                let info = note.userInfo ?? [:]
                MainActor.assumeIsolated { self?.heard(app, info) }
            }
        }
    }

    // A player's own broadcast: its state, track and length (Spotify says where it is; Music is asked).
    private func heard(_ app: String, _ info: [AnyHashable: Any]) {
        let state = info["Player State"] as? String ?? ""
        guard state != "Stopped", let title = info["Name"] as? String, !title.isEmpty else {
            if player?.state.app == app { player = nil; choose() }
            return
        }
        let playing = state == "Playing"
        let length = ((info["Total Time"] ?? info["Duration"]) as? Double ?? 0) / 1000
        // Spotify sends its position; for Music, carry on from where this track was, or start it from the top.
        var elapsed = info["Playback Position"] as? Double
            ?? (player?.state.app == app && player?.state.title == title ? player!.state.position() : 0)
        if elapsed > length, length > 0 { elapsed = 0 }
        let next = NowPlaying(app: app, playing: playing, title: title, artist: info["Artist"] as? String ?? "",
                              album: info["Album"] as? String ?? "", duration: length, elapsed: elapsed,
                              timestamp: Date().timeIntervalSince1970)
        player = (next, Date())
        if app == "Music" && playing { askPosition() }
        choose()
    }

    // Music doesn't broadcast where it is in a track; asking needs the Automation permission, which macOS asks once.
    private func askPosition() {
        queue.async {
            let position = Self.script("tell application \"Music\" to get player position")?.doubleValue
            Task { @MainActor in
                guard let position, var current = self.player, current.state.app == "Music" else { return }
                current.state.elapsed = position
                current.state.timestamp = Date().timeIntervalSince1970
                self.player = current
                self.choose()
            }
        }
    }

    private func choose() {
        let sys = system.map { (s: $0.state, at: $0.at) }
        let own = player.map { (s: $0.state, at: $0.at) }
        let pick: NowPlaying?
        var isDirect = false
        switch (sys, own) {
        case let (a?, b?) where b.s.playing && (!a.s.playing || a.s.title.isEmpty || b.at > a.at) && a.s.app != b.s.app:
            pick = b.s; isDirect = true
        case let (a?, b?) where !a.s.playing && a.s.title.isEmpty:
            pick = b.s; isDirect = true
        case let (a?, _):
            pick = a.s
        case let (nil, b?):
            pick = b.s; isDirect = true
        default:
            pick = nil
        }
        direct = isDirect ? pick?.app : nil
        show(pick, artwork: isDirect ? nil : pendingArtwork)
    }

    private var pendingArtwork: Data?
    private var dropArtwork = false

    // Whether a picture is just the app's own icon, compared small against what Finder shows for the app.
    nonisolated private static func isAppIcon(_ data: Data, _ bundle: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle),
              let given = NSImage(data: data).flatMap(Self.pixels), let icon = Self.pixels(NSWorkspace.shared.icon(forFile: url.path)) else { return false }
        let difference = zip(given, icon).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
        return Double(difference) / Double(given.count) < 28
    }

    nonisolated private static func pixels(_ image: NSImage) -> [UInt8]? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let side = 12
        var out = [UInt8](repeating: 0, count: side * side * 4)
        let ok: Bool = out.withUnsafeMutableBytes { buffer in
            guard let ctx = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return ok ? out : nil
    }

    func setActive(_ active: Bool) {
        if active { refreshVolume() }
    }

    private func start() {
        guard let lib = Self.library, FileManager.default.fileExists(atPath: lib) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        process.arguments = ["-e", Self.perl("beanotch_stream"), lib]
        let output = Pipe(), input = Pipe()
        process.standardOutput = output
        // The helper exits when this pipe closes, which happens when Beanotch quits for any reason.
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
        // macOS doesn't always announce a change of player (a browser tab starting, say); a nudge every two seconds
        // has the helper report again, so the notch never sticks on the last one.
        poll?.invalidate()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { try? self?.keepAlive?.fileHandleForWriting.write(contentsOf: Data("x".utf8)) }
        }
        t.tolerance = 0.5
        RunLoop.main.add(t, forMode: .common)
        poll = t
    }

    private var poll: Timer?

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
            system = nil
            choose()
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
        // A new playing state, or a new track, counts as the system changing; the clock ticking along doesn't.
        if system?.state.playing != next.playing || system?.state.title != next.title { system = (next, Date()) }
        else { system?.state = next }
        pendingArtwork = (json["artwork"] as? String).flatMap { Data(base64Encoded: $0) }
        // A browser with nothing better (a page without a cover) gives its own icon; that isn't the song's.
        if let data = pendingArtwork, let bundle = json["bundle"] as? String, Self.isAppIcon(data, bundle) { pendingArtwork = nil; dropArtwork = true }
        else if pendingArtwork != nil { dropArtwork = false }
        choose()
    }

    private func show(_ next: NowPlaying?, artwork data: Data?) {
        guard let next else {
            now = nil
            artwork = nil
            lyrics.clear()
            return
        }
        if next.title != now?.title || next.artist != now?.artist {
            artwork = nil
            if next.playing, !next.title.isEmpty { onTrackChange?(next) }
            if direct != nil { fetchArtwork(next) }
        }
        if let data { artwork = NSImage(data: data) }
        else if dropArtwork && direct == nil { artwork = nil }
        if next != now { now = next }
        lyrics.load(title: next.title, artist: next.artist, duration: next.duration)
    }

    // A player's own broadcast carries no picture: the cover comes from Apple's free iTunes search.
    private func fetchArtwork(_ track: NowPlaying) {
        var url = URLComponents(string: "https://itunes.apple.com/search")!
        url.queryItems = [.init(name: "term", value: "\(track.artist) \(track.title)"), .init(name: "entity", value: "song"), .init(name: "limit", value: "1")]
        guard let search = url.url else { return }
        Task {
            guard let (data, _) = try? await URLSession.shared.data(from: search),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let small = (json["results"] as? [[String: Any]])?.first?["artworkUrl100"] as? String,
                  let big = URL(string: small.replacingOccurrences(of: "100x100", with: "600x600")),
                  let (image, _) = try? await URLSession.shared.data(from: big) else { return }
            if now?.title == track.title { artwork = NSImage(data: image) }
        }
    }

    func playPause() {
        if var n = now {
            n.elapsed = n.position()
            n.timestamp = Date().timeIntervalSince1970
            n.playing.toggle()
            now = n
        }
        if let app = direct { tell(app, "playpause") } else { send("2") }
    }

    func next() { if let app = direct { tell(app, "next track") } else { send("4") } }
    func previous() { if let app = direct { tell(app, "previous track") } else { send("5") } }
    func seek(_ t: Double) { if let app = direct { tell(app, "set player position to \(t)") } else { send("seek:\(t)") } }

    private func tell(_ app: String, _ command: String) {
        queue.async { _ = Self.script("tell application \"\(app)\" to \(command)") }
    }

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
                if let app = self?.direct { self?.tell(app, "pause") } else { self?.send("1") }
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
        let script = Self.perl("beanotch_send")
        queue.async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
            process.arguments = ["-e", script, lib]
            process.environment = ["BEANOTCH_CMD": command]
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
