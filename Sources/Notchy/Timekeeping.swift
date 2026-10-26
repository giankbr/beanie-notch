import AppKit

// A plain countdown (tea, laundry, a call in ten minutes), apart from the focus timer.
@MainActor
final class CountdownTimer: ObservableObject {
    static let presets = [1, 3, 5, 10, 15, 30]

    @Published private(set) var endDate: Date?
    @Published private(set) var duration: TimeInterval = 5 * 60
    var onDone: (() -> Void)?
    private var timer: Timer?

    var isRunning: Bool { endDate != nil }

    func left(at date: Date = Date()) -> TimeInterval {
        endDate.map { max(0, $0.timeIntervalSince(date)) } ?? duration
    }

    func start(minutes: Int) {
        duration = TimeInterval(minutes * 60)
        endDate = Date().addingTimeInterval(duration)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.endDate = nil
                self?.onDone?()
            }
        }
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
        endDate = nil
    }
}

// The time in other cities, kept between launches.
@MainActor
final class WorldClock: ObservableObject {
    struct City: Hashable {
        let name: String
        let zone: String
    }

    static let choices: [City] = [
        City(name: "London", zone: "Europe/London"), City(name: "Paris", zone: "Europe/Paris"),
        City(name: "Berlin", zone: "Europe/Berlin"), City(name: "Amsterdam", zone: "Europe/Amsterdam"),
        City(name: "Istanbul", zone: "Europe/Istanbul"), City(name: "Cairo", zone: "Africa/Cairo"),
        City(name: "Mecca", zone: "Asia/Riyadh"), City(name: "Dubai", zone: "Asia/Dubai"),
        City(name: "Mumbai", zone: "Asia/Kolkata"), City(name: "Jakarta", zone: "Asia/Jakarta"),
        City(name: "Makassar", zone: "Asia/Makassar"), City(name: "Jayapura", zone: "Asia/Jayapura"),
        City(name: "Singapore", zone: "Asia/Singapore"), City(name: "Kuala Lumpur", zone: "Asia/Kuala_Lumpur"),
        City(name: "Hong Kong", zone: "Asia/Hong_Kong"), City(name: "Seoul", zone: "Asia/Seoul"),
        City(name: "Tokyo", zone: "Asia/Tokyo"), City(name: "Sydney", zone: "Australia/Sydney"),
        City(name: "New York", zone: "America/New_York"), City(name: "Chicago", zone: "America/Chicago"),
        City(name: "Los Angeles", zone: "America/Los_Angeles"), City(name: "São Paulo", zone: "America/Sao_Paulo"),
    ]

    @Published private(set) var cities: [City] = []

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: "worldClock") ?? ["Europe/London", "Asia/Tokyo", "America/New_York"]
        cities = saved.compactMap { zone in Self.choices.first { $0.zone == zone } }
    }

    func add(_ city: City) {
        guard !cities.contains(city) else { return }
        cities.append(city)
        save()
    }

    func remove(_ city: City) {
        cities.removeAll { $0 == city }
        save()
    }

    private func save() {
        UserDefaults.standard.set(cities.map(\.zone), forKey: "worldClock")
    }
}

// A scratchpad that saves as you type, and can become a text file on the Shelf.
@MainActor
final class Notes: ObservableObject {
    @Published var text: String {
        didSet { scheduleSave() }
    }
    private var saveWork: DispatchWorkItem?

    init() {
        text = UserDefaults.standard.string(forKey: "note") ?? ""
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { UserDefaults.standard.set(self?.text, forKey: "note") }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    // Written under Application Support, named after its first line.
    func exportFile() -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchy/Notes")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let firstLine = trimmed.split(separator: "\n").first.map(String.init) ?? "Note"
        let name = String(firstLine.filter { !"/:\\".contains($0) }.prefix(40)).trimmingCharacters(in: .whitespaces)
        let url = folder.appendingPathComponent((name.isEmpty ? "Note" : name) + ".txt")
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }
}

// Looks for a newer release on GitHub. The repository has to be public for this to get an answer.
@MainActor
final class Updater: ObservableObject {
    static let repository = "giankbr/notchy"

    @Published private(set) var latest: String?
    @Published private(set) var page: URL?
    @Published private(set) var checking = false
    @Published private(set) var failed = false
    @Published var automatic: Bool {
        didSet { UserDefaults.standard.set(automatic, forKey: "checkUpdates") }
    }
    var onNewVersion: ((String) -> Void)?
    private var timer: Timer?

    var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0" }
    var updateAvailable: Bool { latest.map { Self.newer($0, than: current) } ?? false }

    init() {
        automatic = UserDefaults.standard.object(forKey: "checkUpdates") as? Bool ?? true
        let t = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { if self?.automatic == true { self?.check(announce: true) } }
        }
        t.tolerance = 3600
        timer = t
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            MainActor.assumeIsolated { if self?.automatic == true { self?.check(announce: true) } }
        }
    }

    func check(announce: Bool = false) {
        guard !checking else { return }
        checking = true
        failed = false
        Task {
            struct Release: Decodable { let tag_name: String; let html_url: String }
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest")!, timeoutInterval: 10)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let release: Release? = await {
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                return try? JSONDecoder().decode(Release.self, from: data)
            }()
            checking = false
            guard let release else {
                failed = true
                return
            }
            let version = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            latest = version
            page = URL(string: release.html_url)
            if announce, updateAvailable { onNewVersion?(version) }
        }
    }

    static func newer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
