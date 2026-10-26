import Foundation

// Current weather and the next hours from Open-Meteo (free, no key), for the place set in Prayer Times.
// Asked only when the Today page shows, at most every 30 minutes.
@MainActor
final class Weather: ObservableObject {
    struct Hour: Identifiable {
        let time: Date
        let temp: Double
        let code: Int
        var id: Date { time }
    }

    struct Report {
        let temp: Double
        let code: Int
        let high: Double
        let low: Double
        let hours: [Hour]
    }

    @Published private(set) var report: Report?
    @Published private(set) var failed = false
    private var fetchedAt = Date.distantPast
    private var key = ""

    func refresh(for place: PrayerTimes.Place?) {
        guard let place else { return }
        let newKey = "\(place.lat),\(place.lng)"
        guard newKey != key || Date().timeIntervalSince(fetchedAt) > 1800 else { return }
        key = newKey
        fetchedAt = Date()
        Task {
            let result = await Self.fetch(lat: place.lat, lng: place.lng)
            guard key == newKey else { return }
            report = result
            failed = result == nil
        }
    }

    private struct Response: Decodable {
        struct Current: Decodable {
            let temperature_2m: Double
            let weather_code: Int
        }
        struct Hourly: Decodable {
            let time: [String]
            let temperature_2m: [Double]
            let weather_code: [Int]
        }
        struct Daily: Decodable {
            let temperature_2m_max: [Double]
            let temperature_2m_min: [Double]
        }
        let utc_offset_seconds: Int
        let current: Current
        let hourly: Hourly
        let daily: Daily
    }

    nonisolated private static func fetch(lat: Double, lng: Double) async -> Report? {
        let url = URL(string: "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lng)"
            + "&current=temperature_2m,weather_code&hourly=temperature_2m,weather_code"
            + "&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=2")!
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let r = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let parse = DateFormatter()
        parse.dateFormat = "yyyy-MM-dd'T'HH:mm"
        parse.timeZone = TimeZone(secondsFromGMT: r.utc_offset_seconds)
        let now = Date()
        let hours = zip(r.hourly.time, zip(r.hourly.temperature_2m, r.hourly.weather_code))
            .compactMap { t, v in parse.date(from: t).map { Hour(time: $0, temp: v.0, code: v.1) } }
            .filter { $0.time > now }
            .prefix(5)
        return Report(temp: r.current.temperature_2m, code: r.current.weather_code,
                      high: r.daily.temperature_2m_max.first ?? 0, low: r.daily.temperature_2m_min.first ?? 0, hours: Array(hours))
    }

    // WMO weather codes, as Open-Meteo reports them.
    nonisolated static func symbol(_ code: Int) -> String {
        switch code {
        case 0: "sun.max.fill"
        case 1, 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51...57: "cloud.drizzle.fill"
        case 61...67, 80...82: "cloud.rain.fill"
        case 71...77, 85, 86: "cloud.snow.fill"
        case 95...99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }

    nonisolated static func describe(_ code: Int) -> String {
        switch code {
        case 0: "Clear"
        case 1, 2: "Partly cloudy"
        case 3: "Cloudy"
        case 45, 48: "Fog"
        case 51...57: "Drizzle"
        case 61...67: "Rain"
        case 80...82: "Showers"
        case 71...77, 85, 86: "Snow"
        case 95...99: "Thunderstorm"
        default: "—"
        }
    }
}
