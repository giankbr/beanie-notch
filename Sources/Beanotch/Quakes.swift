import AppKit

// Earthquakes from BMKG, Indonesia's agency, for a place in Indonesia: its public feed of the latest quake is read
// every minute. One near enough to be felt, a strong one anywhere in the country, or one that may bring a tsunami
// shows in the notch in red, with BMKG's shake map a click away.
@MainActor
final class Quakes: ObservableObject {
    struct Quake: Equatable {
        let id: String
        let magnitude: Double
        let lat: Double
        let lng: Double
        let depth: String
        let region: String
        let tsunami: Bool
        let shakemap: URL?
    }

    @Published private(set) var latest: Quake?
    var onNotice: ((Notice) -> Void)?
    var place: (() -> PrayerTimes.Place?)?
    private var timer: Timer?
    private var seen: String? = UserDefaults.standard.string(forKey: "quakeSeen")

    private static let feed = URL(string: "https://data.bmkg.go.id/DataMKG/TEWS/autogempa.json")!
    private static let near = 300.0, strong = 6.0

    func setEnabled(_ on: Bool) {
        timer?.invalidate()
        timer = nil
        guard on else { return }
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
        poll()
    }

    private func poll() {
        Task { await check() }
    }

    func check() async {
        guard let place = place?(), PrayerTimes.inIndonesia(place),
              let (data, _) = try? await URLSession.shared.data(from: Self.feed),
              let quake = Self.parse(data) else { return }
        latest = quake
        guard quake.id != seen else { return }
        let first = seen == nil
        seen = quake.id
        UserDefaults.standard.set(quake.id, forKey: "quakeSeen")
        // The first read only sets where to start from; an old quake isn't news.
        guard !first else { return }
        let km = PrayerTimes.distance(place, quake.lat, quake.lng)
        guard km <= Self.near || quake.magnitude >= Self.strong || quake.tsunami else { return }
        NSSound(named: "Sosumi")?.play()
        // Magnitudes are written with a point everywhere.
        let magnitude = String(format: "%.1f", quake.magnitude)
        onNotice?(Notice(icon: quake.tsunami ? "water.waves" : "waveform.path.ecg", color: Theme.red,
                         left: quake.tsunami ? "Tsunami risk · M\(magnitude)" : "Earthquake M\(magnitude)",
                         right: "\(Int(km.rounded())) km away · \(quake.depth) deep", duration: 20, essential: true,
                         open: quake.shakemap))
    }

    static func parse(_ data: Data) -> Quake? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let g = (json["Infogempa"] as? [String: Any])?["gempa"] as? [String: Any],
              let id = g["DateTime"] as? String,
              let coordinates = (g["Coordinates"] as? String)?.split(separator: ",").compactMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
              coordinates.count == 2,
              let magnitude = Double(g["Magnitude"] as? String ?? "") else { return nil }
        let potential = (g["Potensi"] as? String ?? "").lowercased()
        return Quake(id: id, magnitude: magnitude, lat: coordinates[0], lng: coordinates[1],
                     depth: g["Kedalaman"] as? String ?? "?", region: g["Wilayah"] as? String ?? "",
                     tsunami: potential.contains("tsunami") && !potential.contains("tidak berpotensi"),
                     shakemap: (g["Shakemap"] as? String).flatMap { URL(string: "https://data.bmkg.go.id/DataMKG/TEWS/" + $0) })
    }
}
