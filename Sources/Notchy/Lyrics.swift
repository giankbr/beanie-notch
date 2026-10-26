import Foundation

// Synced lyrics from LRCLIB (lrclib.net), a free, keyless lyrics library. Asked once per song.
@MainActor
final class Lyrics: ObservableObject {
    struct Line: Equatable {
        let time: Double
        let text: String
    }

    enum State: Equatable { case idle, loading, synced, plain, none }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var plain = ""
    @Published private(set) var state: State = .idle
    var enabled = true
    private var key = ""
    private var task: Task<Void, Never>?

    func load(title: String, artist: String, duration: Double) {
        let newKey = "\(title)|\(artist)"
        guard newKey != key else { return }
        key = newKey
        task?.cancel()
        lines = []
        plain = ""
        guard enabled, !title.isEmpty else {
            state = .idle
            return
        }
        state = .loading
        let (track, singer) = Self.clean(title: title, artist: artist)
        task = Task {
            let found = await Self.fetch(track: track, artist: singer, duration: duration)
            guard !Task.isCancelled, key == newKey else { return }
            if let synced = found?.synced, !synced.isEmpty {
                lines = synced
                state = .synced
            } else if let text = found?.plain, !text.isEmpty {
                plain = text
                state = .plain
            } else {
                state = .none
                // Nothing came back (offline, or LRCLIB busy): the next playback update asks again.
                if found == nil { key = "" }
            }
        }
    }

    func clear() {
        key = ""
        task?.cancel()
        lines = []
        plain = ""
        state = .idle
    }

    // The index of the line being sung at `position` seconds.
    func index(at position: Double) -> Int? {
        lines.lastIndex { $0.time <= position + 0.25 }
    }

    // YouTube titles often read "Artist - Song (Official Video)" with the channel ("Artist - Topic") as artist.
    nonisolated static func clean(title: String, artist: String) -> (String, String) {
        var track = title
        var singer = artist.replacingOccurrences(of: " - Topic", with: "").replacingOccurrences(of: "VEVO", with: "")
        if let dash = track.range(of: " - ") {
            let left = String(track[..<dash.lowerBound])
            if singer.isEmpty || left.localizedCaseInsensitiveContains(singer) || singer.localizedCaseInsensitiveContains(left) {
                singer = singer.isEmpty ? left : singer
                track = String(track[dash.upperBound...])
            }
        }
        track = track.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        track = track.replacingOccurrences(of: #"\s+(feat\.|ft\.|featuring)\s.*$"#, with: "", options: [.regularExpression, .caseInsensitive])
        return (track.trimmingCharacters(in: .whitespaces), singer.trimmingCharacters(in: .whitespaces))
    }

    private struct Record: Decodable {
        let duration: Double?
        let syncedLyrics: String?
        let plainLyrics: String?
    }

    private typealias Found = (synced: [Line]?, plain: String?)

    // Four free, keyless sources asked at once: LRCLIB, then NetEase Cloud Music, QQ Music and Kugou, whose
    // catalogues reach more Asian and Indonesian releases. Timed lyrics from any of them beat plain text from another.
    nonisolated private static func fetch(track: String, artist: String, duration: Double) async -> Found? {
        async let lrclib = fromLRCLIB(track: track, artist: artist, duration: duration)
        async let netease = fromNetEase(track: track, artist: artist, duration: duration)
        async let qq = fromQQ(track: track, artist: artist, duration: duration)
        async let kugou = fromKugou(track: track, artist: artist, duration: duration)
        let all = await [lrclib, netease, qq, kugou]
        let plain = all.compactMap { $0?.plain }.first { !$0.isEmpty }
        if let synced = all.compactMap({ $0?.synced }).first(where: { !$0.isEmpty }) { return (synced, plain) }
        return plain.map { (nil, $0) }
    }

    nonisolated private static func fromLRCLIB(track: String, artist: String, duration: Double) async -> Found? {
        var query = [URLQueryItem(name: "track_name", value: track)]
        if !artist.isEmpty { query.append(URLQueryItem(name: "artist_name", value: artist)) }
        var records = await search(query)
        if records.isEmpty { records = await search([URLQueryItem(name: "q", value: "\(artist) \(track)")]) }
        guard !records.isEmpty else { return nil }
        // The closest length wins, so a live or extended version doesn't get the studio cut's timing.
        func gap(_ r: Record) -> Double { duration > 0 ? abs((r.duration ?? 0) - duration) : 0 }
        let synced = records.filter { $0.syncedLyrics?.isEmpty == false && gap($0) < 8 }.min { gap($0) < gap($1) }
        if let synced { return (parse(synced.syncedLyrics ?? ""), synced.plainLyrics) }
        return records.first { $0.plainLyrics?.isEmpty == false }.map { (nil, $0.plainLyrics) }
    }

    nonisolated private static func search(_ query: [URLQueryItem]) async -> [Record] {
        var components = URLComponents(string: "https://lrclib.net/api/search")!
        components.queryItems = query
        guard let url = components.url else { return [] }
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Notchy/1.0 (macOS notch app)", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        return (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    nonisolated private static func fromNetEase(track: String, artist: String, duration: Double) async -> Found? {
        struct Search: Decodable {
            struct Result: Decodable { let songs: [Song]? }
            struct Song: Decodable { let id: Int; let name: String; let artists: [Artist]; let duration: Double? }
            struct Artist: Decodable { let name: String }
            let result: Result?
        }
        struct Lyric: Decodable {
            struct Lrc: Decodable { let lyric: String? }
            let lrc: Lrc?
        }
        let referer = "https://music.163.com"
        guard let searchURL = Self.url("https://music.163.com/api/search/get", ["s": "\(artist) \(track)", "type": "1", "limit": "8"]),
              let results: Search = await request(searchURL, referer: referer),
              let song = results.result?.songs?.first(where: {
                  matches($0.name, $0.artists.map(\.name), length: ($0.duration ?? 0) / 1000, track, artist, duration)
              }),
              let lyricURL = Self.url("https://music.163.com/api/song/lyric", ["id": "\(song.id)", "lv": "1"]),
              let lyric: Lyric = await request(lyricURL, referer: referer),
              let text = lyric.lrc?.lyric else { return nil }
        return Self.found(fromLRC: text)
    }

    nonisolated private static func fromQQ(track: String, artist: String, duration: Double) async -> Found? {
        struct Search: Decodable {
            struct DataBlock: Decodable { let song: Songs }
            struct Songs: Decodable { let list: [Song] }
            struct Song: Decodable { let songmid: String; let songname: String; let singer: [Singer]; let interval: Double? }
            struct Singer: Decodable { let name: String }
            let data: DataBlock?
        }
        struct Lyric: Decodable {
            struct Block: Decodable { let data: Inner? }
            struct Inner: Decodable { let lyric: String? }
            let lyric: Block?
        }
        let referer = "https://y.qq.com"
        guard let searchURL = Self.url("https://c.y.qq.com/soso/fcgi-bin/client_search_cp",
                                       ["w": "\(artist) \(track)", "format": "json", "p": "1", "n": "8"]),
              let results: Search = await request(searchURL, referer: referer),
              let song = results.data?.song.list.first(where: {
                  matches($0.songname, $0.singer.map(\.name), length: $0.interval ?? 0, track, artist, duration)
              }) else { return nil }
        let body = #"{"comm":{"ct":24,"cv":0},"lyric":{"module":"music.musichallSong.PlayLyricInfo","#
            + #""method":"GetPlayLyricInfo","param":{"songMID":"\#(song.songmid)","songID":0}}}"#
        guard let lyric: Lyric = await request(URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!, referer: referer,
                                               body: Data(body.utf8)),
              let encoded = lyric.lyric?.data?.lyric,
              let decoded = Data(base64Encoded: encoded).flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
        return Self.found(fromLRC: decoded)
    }

    nonisolated private static func fromKugou(track: String, artist: String, duration: Double) async -> Found? {
        struct Search: Decodable {
            struct Candidate: Decodable { let id: String; let accesskey: String; let song: String; let singer: String; let duration: Double }
            let candidates: [Candidate]?
        }
        struct Lyric: Decodable { let content: String? }
        let referer = "https://www.kugou.com"
        var query = ["keyword": "\(artist) - \(track)", "ver": "1", "man": "yes", "client": "pc"]
        if duration > 0 { query["duration"] = "\(Int(duration * 1000))" }
        guard let searchURL = Self.url("https://lyrics.kugou.com/search", query),
              let results: Search = await request(searchURL, referer: referer),
              let song = results.candidates?.first(where: {
                  // Kugou lists several singers as "A、B".
                  matches($0.song, $0.singer.components(separatedBy: "、"), length: $0.duration / 1000, track, artist, duration)
              }),
              let lyricURL = Self.url("https://lyrics.kugou.com/download",
                                      ["id": song.id, "accesskey": song.accesskey, "fmt": "lrc", "charset": "utf8", "ver": "1", "client": "pc"]),
              let lyric: Lyric = await request(lyricURL, referer: referer),
              let encoded = lyric.content,
              let decoded = Data(base64Encoded: encoded).flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
        return Self.found(fromLRC: decoded)
    }

    nonisolated private static func url(_ base: String, _ query: [String: String]) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components?.url
    }

    nonisolated private static func request<T: Decodable>(_ url: URL, referer: String, body: Data? = nil) async -> T? {
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Notchy/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    // Same title, a shared artist, and about the same length, so a remix or a cover isn't taken for the song.
    nonisolated private static func matches(_ name: String, _ artists: [String], length: Double,
                                            _ track: String, _ artist: String, _ duration: Double) -> Bool {
        func key(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        guard !key(track).isEmpty, key(name) == key(track) else { return false }
        if !artist.isEmpty {
            let wanted = key(artist)
            guard artists.contains(where: { key($0).contains(wanted) || wanted.contains(key($0)) }) else { return false }
        }
        return duration <= 0 || length <= 0 || abs(length - duration) < 10
    }

    nonisolated private static func found(fromLRC text: String) -> Found? {
        let lines = parse(text)
        if lines.count >= 3 { return (lines, lines.map(\.text).joined(separator: "\n")) }
        let plain = text.split(separator: "\n")
            .map { $0.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !isCredit($0) }
            .joined(separator: "\n")
        return plain.isEmpty ? nil : (nil, plain)
    }

    // NetEase, QQ and Kugou open their lyrics with credit lines (lyricist, composer, producer).
    nonisolated private static func isCredit(_ text: String) -> Bool {
        if ["作词", "作曲", "编曲", "制作", "混音", "母带", "纯音乐", "词：", "曲："].contains(where: { text.contains($0) }) { return true }
        return text.range(of: #"^(lyrics|words|music|composed|written|produced|arranged|mixed|mastered)( by)?\s*[:：]"#,
                          options: [.regularExpression, .caseInsensitive]) != nil
    }

    nonisolated private static func parse(_ lrc: String) -> [Line] {
        let pattern = try! NSRegularExpression(pattern: #"^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$"#)
        return lrc.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            guard let m = pattern.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let min = Range(m.range(at: 1), in: line), let sec = Range(m.range(at: 2), in: line),
                  let text = Range(m.range(at: 3), in: line) else { return nil }
            let words = String(line[text]).trimmingCharacters(in: .whitespaces)
            if isCredit(words) { return nil }
            return Line(time: (Double(line[min]) ?? 0) * 60 + (Double(line[sec]) ?? 0), text: words.isEmpty ? "♪" : words)
        }
    }
}
