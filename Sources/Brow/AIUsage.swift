import Foundation

// What AI coding tools have used, read from the logs they keep on this Mac. Nothing is sent anywhere and no
// sign-in is touched: Claude Code writes every request's token counts to ~/.claude/projects, Codex writes its
// token counts and rate-limit windows to ~/.codex/sessions.
@MainActor
final class AIUsage: ObservableObject {
    struct Totals: Equatable {
        var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
        var cost = 0.0
        var requests = 0
        var tokens: Int { input + output + cacheRead + cacheWrite }

        mutating func add(_ r: UsageRecord) {
            input += r.input; output += r.output; cacheRead += r.cacheRead; cacheWrite += r.cacheWrite5m + r.cacheWrite1h
            cost += r.cost
            requests += 1
        }
    }

    struct Limit: Equatable {
        let label: String
        let percent: Double
        let resets: Date?
    }

    struct Provider: Identifiable, Equatable {
        let id: String
        let name: String
        var detected = false
        var today = Totals()
        var window = Totals()
        var week = Totals()
        var days: [Double] = Array(repeating: 0, count: 7)
        var models: [(name: String, totals: Totals)] = []
        var limits: [Limit] = []
        var priced = true

        static func == (a: Provider, b: Provider) -> Bool {
            a.id == b.id && a.today == b.today && a.week == b.week && a.window == b.window && a.limits == b.limits && a.detected == b.detected
        }
    }

    @Published private(set) var providers: [Provider] = []
    @Published private(set) var updated: Date?
    private let scanner = UsageScanner()
    private var timer: Timer?
    private var refreshing = false

    // Read while the page is on screen, every minute.
    func setActive(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        t.tolerance = 10
        timer = t
    }

    func refresh() {
        guard !refreshing else { return }
        refreshing = true
        Task {
            let result = await scanner.scan()
            providers = result
            updated = Date()
            refreshing = false
        }
    }
}

struct UsageRecord: Sendable {
    let date: Date
    let model: String
    let input: Int, output: Int, cacheRead: Int, cacheWrite5m: Int, cacheWrite1h: Int

    // At Anthropic API list prices: what the same tokens would cost on the API, not what a subscription charges.
    var cost: Double {
        guard let p = Pricing.claude(model) else { return 0 }
        return (Double(input) * p.input + Double(output) * p.output + Double(cacheRead) * p.cacheRead
                + Double(cacheWrite5m) * p.input * 1.25 + Double(cacheWrite1h) * p.input * 2) / 1_000_000
    }
}

enum Pricing {
    struct Rate { let input: Double; let output: Double; let cacheRead: Double }

    // Per million tokens. Cache writes are 1.25× input (5-minute) and 2× input (1-hour).
    static func claude(_ model: String) -> Rate? {
        let m = model.lowercased()
        let table: [(String, Rate)] = [
            ("fable-5-1", Rate(input: 10, output: 50, cacheRead: 0.25)), ("mythos-5-1", Rate(input: 10, output: 50, cacheRead: 0.25)),
            ("fable-5", Rate(input: 10, output: 50, cacheRead: 1)), ("mythos", Rate(input: 10, output: 50, cacheRead: 1)),
            ("opus-5-5", Rate(input: 4, output: 20, cacheRead: 0.2)), ("opus-5", Rate(input: 5, output: 25, cacheRead: 0.5)),
            ("opus-4-8", Rate(input: 5, output: 25, cacheRead: 0.5)), ("opus-4-7", Rate(input: 5, output: 25, cacheRead: 0.5)),
            ("opus-4-6", Rate(input: 5, output: 25, cacheRead: 0.5)), ("opus-4-5", Rate(input: 5, output: 25, cacheRead: 0.5)),
            ("opus-4", Rate(input: 15, output: 75, cacheRead: 1.5)),
            ("sonnet-5", Rate(input: 2, output: 10, cacheRead: 0.2)), ("sonnet-4", Rate(input: 3, output: 15, cacheRead: 0.3)),
            ("haiku-5-5", Rate(input: 0.1, output: 0.5, cacheRead: 0.01)), ("haiku-4-5", Rate(input: 1, output: 5, cacheRead: 0.1)),
        ]
        return table.first { m.contains($0.0) }?.1
    }
}

// Keeps what it has read of each log, and on the next pass reads only the bytes added since.
actor UsageScanner {
    private struct FileState { var offset: UInt64 = 0 }
    private var files: [String: FileState] = [:]
    private var claude: [String: UsageRecord] = [:]
    private var codex: [String: (date: Date, input: Int, cached: Int, output: Int)] = [:]
    private var codexLimits: (date: Date, limits: [AIUsage.Limit])?
    private let fm = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser

    func scan() -> [AIUsage.Provider] {
        let since = Date().addingTimeInterval(-8 * 86400)
        let claudeRoot = home.appendingPathComponent(".claude/projects")
        let codexRoot = home.appendingPathComponent(".codex/sessions")
        for url in logs(under: claudeRoot, since: since) { read(url, claudeLine) }
        for url in logs(under: codexRoot, since: since) { read(url) { self.codexLine($0, file: url.path) } }
        claude = claude.filter { $0.value.date > since }
        codex = codex.filter { $0.value.date > since }
        return [claudeProvider(detected: fm.fileExists(atPath: claudeRoot.path)),
                codexProvider(detected: fm.fileExists(atPath: codexRoot.path))]
    }

    private func logs(under root: URL, since: Date) -> [URL] {
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else { return [] }
        return e.compactMap { $0 as? URL }.filter {
            $0.pathExtension == "jsonl"
                && ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast) > since
        }
    }

    // Only whole lines are taken; a line still being written is picked up next time.
    private func read(_ url: URL, _ handle: (Data) -> Void) {
        guard let file = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? file.close() }
        var state = files[url.path] ?? FileState()
        let size = (try? file.seekToEnd()) ?? 0
        if size < state.offset { state.offset = 0 }
        guard size > state.offset else { return }
        try? file.seek(toOffset: state.offset)
        guard let data = try? file.readToEnd() else { return }
        var start = data.startIndex
        var consumed = 0
        while let newline = data[start...].firstIndex(of: 0x0A) {
            handle(data[start..<newline])
            consumed = newline - data.startIndex + 1
            start = data.index(after: newline)
        }
        state.offset += UInt64(consumed)
        files[url.path] = state
    }

    private static let usageMarker = Data("\"usage\"".utf8)
    private static let tokenMarker = Data("token_count".utf8)
    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    nonisolated(unsafe) private static let isoPlain = ISO8601DateFormatter()

    private static func date(_ text: Any?) -> Date? {
        guard let text = text as? String else { return nil }
        return iso.date(from: text) ?? isoPlain.date(from: text)
    }

    private func claudeLine(_ line: Data) {
        guard line.range(of: Self.usageMarker) != nil,
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let message = json["message"] as? [String: Any], let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, model != "<synthetic>",
              let date = Self.date(json["timestamp"]) else { return }
        // A response is logged once per content block; the message and request ids make it one request.
        let key = "\(message["id"] as? String ?? UUID().uuidString)|\(json["requestId"] as? String ?? "")"
        guard claude[key] == nil else { return }
        let creation = usage["cache_creation"] as? [String: Any]
        let write1h = creation?["ephemeral_1h_input_tokens"] as? Int ?? 0
        let writeTotal = usage["cache_creation_input_tokens"] as? Int ?? 0
        claude[key] = UsageRecord(date: date, model: model, input: usage["input_tokens"] as? Int ?? 0,
                                  output: usage["output_tokens"] as? Int ?? 0, cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                                  cacheWrite5m: max(0, writeTotal - write1h), cacheWrite1h: write1h)
    }

    private func codexLine(_ line: Data, file: String) {
        guard line.range(of: Self.tokenMarker) != nil,
              let json = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = json["payload"] as? [String: Any], payload["type"] as? String == "token_count",
              let date = Self.date(json["timestamp"]) else { return }
        if let info = payload["info"] as? [String: Any], let last = info["last_token_usage"] as? [String: Any] {
            codex["\(file)|\(json["timestamp"] as? String ?? "")"] = (date, last["input_tokens"] as? Int ?? 0,
                                                                     last["cached_input_tokens"] as? Int ?? 0,
                                                                     (last["output_tokens"] as? Int ?? 0))
        }
        if let limits = payload["rate_limits"] as? [String: Any], date > (codexLimits?.date ?? .distantPast) {
            let parsed = ["primary", "secondary"].compactMap { key -> AIUsage.Limit? in
                guard let window = limits[key] as? [String: Any], let percent = window["used_percent"] as? Double else { return nil }
                let minutes = window["window_minutes"] as? Int ?? 0
                let resets = (window["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                    ?? (window["resets_in_seconds"] as? Double).map { date.addingTimeInterval($0) }
                let label = minutes >= 10_000 ? "Weekly" : minutes > 0 ? "\(minutes / 60) h window" : key.capitalized
                return AIUsage.Limit(label: label, percent: percent, resets: resets)
            }
            codexLimits = (date, parsed)
        }
    }

    private func claudeProvider(detected: Bool) -> AIUsage.Provider {
        var p = AIUsage.Provider(id: "claude", name: "Claude Code", detected: detected)
        let cal = Calendar.current
        let now = Date()
        var byModel: [String: AIUsage.Totals] = [:]
        for r in claude.values {
            if cal.isDateInToday(r.date) {
                p.today.add(r)
                byModel[Self.short(r.model), default: AIUsage.Totals()].add(r)
            }
            if now.timeIntervalSince(r.date) < 5 * 3600 { p.window.add(r) }
            let age = cal.dateComponents([.day], from: cal.startOfDay(for: r.date), to: cal.startOfDay(for: now)).day ?? 99
            if age < 7 {
                p.week.add(r)
                p.days[6 - age] += r.cost
            }
        }
        p.models = byModel.map { ($0.key, $0.value) }.sorted { $0.totals.cost > $1.totals.cost }
        return p
    }

    private func codexProvider(detected: Bool) -> AIUsage.Provider {
        var p = AIUsage.Provider(id: "codex", name: "Codex", detected: detected, priced: false)
        let cal = Calendar.current
        let now = Date()
        for r in codex.values {
            var t = AIUsage.Totals()
            t.input = r.input - r.cached; t.cacheRead = r.cached; t.output = r.output; t.requests = 1
            func add(_ into: inout AIUsage.Totals) {
                into.input += t.input; into.cacheRead += t.cacheRead; into.output += t.output; into.requests += 1
            }
            if cal.isDateInToday(r.date) { add(&p.today) }
            if now.timeIntervalSince(r.date) < 5 * 3600 { add(&p.window) }
            let age = cal.dateComponents([.day], from: cal.startOfDay(for: r.date), to: cal.startOfDay(for: now)).day ?? 99
            if age < 7 {
                add(&p.week)
                p.days[6 - age] += Double(t.tokens)
            }
        }
        p.limits = codexLimits?.limits ?? []
        return p
    }

    // "claude-opus-5-5" → "Opus 5.5".
    private static func short(_ model: String) -> String {
        let parts = model.replacingOccurrences(of: "claude-", with: "").split(separator: "-")
        guard let family = parts.first else { return model }
        let version = parts.dropFirst().prefix { $0.count <= 2 && $0.allSatisfy(\.isNumber) }.joined(separator: ".")
        return family.capitalized + (version.isEmpty ? "" : " " + version)
    }
}
