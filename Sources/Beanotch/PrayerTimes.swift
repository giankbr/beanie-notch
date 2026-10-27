import AppKit
import CoreLocation

@MainActor
final class PrayerTimes: ObservableObject {
    struct Place: Codable, Equatable, Hashable {
        var name: String
        var lat: Double
        var lng: Double
    }

    struct Entry: Identifiable {
        let name: String
        let time: Date
        let isPrayer: Bool
        var id: String { name }
    }

    enum Method: String, CaseIterable, Identifiable {
        case kemenag, mwl, ummAlQura, egypt, isna
        var id: String { rawValue }

        var title: String {
            switch self {
            case .kemenag: "Kemenag RI"
            case .mwl: "Muslim World League"
            case .ummAlQura: "Umm al-Qura"
            case .egypt: "Egyptian Authority"
            case .isna: "ISNA"
            }
        }

        var fajrAngle: Double {
            switch self {
            case .kemenag: 20
            case .mwl: 18
            case .ummAlQura: 18.5
            case .egypt: 19.5
            case .isna: 15
            }
        }

        // Either an angle below the horizon, or minutes after Maghrib (Umm al-Qura).
        var isha: (angle: Double?, minutes: Double?) {
            switch self {
            case .kemenag: (18, nil)
            case .mwl: (17, nil)
            case .ummAlQura: (nil, 90)
            case .egypt: (17.5, nil)
            case .isna: (15, nil)
            }
        }

        // Kemenag's schedules add a couple of minutes of caution (ihtiyat).
        var ihtiyat: Double { self == .kemenag ? 2 : 0 }
    }

    static let cities: [Place] = [
        Place(name: "Jakarta", lat: -6.2088, lng: 106.8456),
        Place(name: "Bogor", lat: -6.5971, lng: 106.806),
        Place(name: "Depok", lat: -6.4025, lng: 106.7942),
        Place(name: "Tangerang", lat: -6.1783, lng: 106.6319),
        Place(name: "Bekasi", lat: -6.2383, lng: 106.9756),
        Place(name: "Bandung", lat: -6.9175, lng: 107.6191),
        Place(name: "Cirebon", lat: -6.732, lng: 108.5523),
        Place(name: "Semarang", lat: -6.9667, lng: 110.4167),
        Place(name: "Yogyakarta", lat: -7.7956, lng: 110.3695),
        Place(name: "Surakarta", lat: -7.5755, lng: 110.8243),
        Place(name: "Surabaya", lat: -7.2575, lng: 112.7521),
        Place(name: "Malang", lat: -7.9666, lng: 112.6326),
        Place(name: "Denpasar", lat: -8.6705, lng: 115.2126),
        Place(name: "Mataram", lat: -8.5833, lng: 116.1167),
        Place(name: "Kupang", lat: -10.1772, lng: 123.607),
        Place(name: "Banda Aceh", lat: 5.5483, lng: 95.3238),
        Place(name: "Medan", lat: 3.5952, lng: 98.6722),
        Place(name: "Padang", lat: -0.9471, lng: 100.4172),
        Place(name: "Pekanbaru", lat: 0.5071, lng: 101.4478),
        Place(name: "Batam", lat: 1.0456, lng: 104.0305),
        Place(name: "Jambi", lat: -1.6101, lng: 103.6131),
        Place(name: "Palembang", lat: -2.9761, lng: 104.7754),
        Place(name: "Bengkulu", lat: -3.7928, lng: 102.2608),
        Place(name: "Bandar Lampung", lat: -5.3971, lng: 105.2668),
        Place(name: "Pontianak", lat: -0.0263, lng: 109.3425),
        Place(name: "Banjarmasin", lat: -3.3186, lng: 114.5944),
        Place(name: "Balikpapan", lat: -1.2379, lng: 116.8529),
        Place(name: "Samarinda", lat: -0.5022, lng: 117.1536),
        Place(name: "Makassar", lat: -5.1477, lng: 119.4327),
        Place(name: "Palu", lat: -0.8917, lng: 119.8707),
        Place(name: "Kendari", lat: -3.9985, lng: 122.5129),
        Place(name: "Manado", lat: 1.4748, lng: 124.8421),
        Place(name: "Ambon", lat: -3.6954, lng: 128.1814),
        Place(name: "Jayapura", lat: -2.5337, lng: 140.7181),
        Place(name: "Kuala Lumpur", lat: 3.139, lng: 101.6869),
        Place(name: "Singapore", lat: 1.3521, lng: 103.8198),
        Place(name: "Makkah", lat: 21.3891, lng: 39.8579),
        Place(name: "Madinah", lat: 24.5247, lng: 39.5692),
    ]

    @Published var place: Place? {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(place), forKey: "prayerPlace")
            recompute()
        }
    }
    @Published var method: Method {
        didSet { UserDefaults.standard.set(method.rawValue, forKey: "prayerMethod"); recompute() }
    }
    @Published var hanafi: Bool {
        didSet { UserDefaults.standard.set(hanafi, forKey: "prayerHanafi"); recompute() }
    }
    @Published var alerts: Bool {
        didSet { UserDefaults.standard.set(alerts, forKey: "prayerAlerts"); schedule() }
    }
    @Published var reminder: Int {
        didSet { UserDefaults.standard.set(reminder, forKey: "prayerReminder"); schedule() }
    }
    @Published private(set) var today: [Entry] = []
    @Published private(set) var tomorrowFajr: Entry?
    // The prayer (or, in Ramadan, Imsak) coming up within the countdown window, for the closed notch.
    @Published private(set) var soon: Entry?
    private var tomorrowImsak: Entry?
    private var soonTimer: Timer?
    @Published private(set) var locating = false
    @Published var locationError: String?
    var onNotice: ((Notice) -> Void)?

    private let locator = Locator()
    private var timer: Timer?

    static let hijriFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .islamicUmmAlQura)
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "d MMMM y 'H'"
        return f
    }()

    var hijri: String { Self.hijriFormatter.string(from: Date()) }

    var isRamadan: Bool { Calendar(identifier: .islamicUmmAlQura).component(.month, from: Date()) == 9 }

    // In Ramadan, Maghrib is when the fast breaks.
    func label(_ entry: Entry) -> String {
        isRamadan && entry.name == "Maghrib" ? "Buka puasa" : entry.name
    }

    var next: Entry? {
        let now = Date()
        return today.first { $0.isPrayer && $0.time > now } ?? tomorrowFajr
    }

    init() {
        let d = UserDefaults.standard
        place = (d.data(forKey: "prayerPlace")).flatMap { try? JSONDecoder().decode(Place?.self, from: $0) }
        method = Method(rawValue: d.string(forKey: "prayerMethod") ?? "") ?? .kemenag
        hanafi = d.bool(forKey: "prayerHanafi")
        alerts = d.object(forKey: "prayerAlerts") as? Bool ?? true
        reminder = d.object(forKey: "prayerReminder") as? Int ?? 10
        recompute()
        let t = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateSoon() }
        }
        t.tolerance = 5
        soonTimer = t
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }
    }

    func useCurrentLocation() {
        locating = true
        locationError = nil
        locator.request { [weak self] result in
            MainActor.assumeIsolated { self?.located(result) }
        }
    }

    private func located(_ result: Result<CLLocation, LocationFailure>) {
        locating = false
        switch result {
        case .success(let location):
            let lat = location.coordinate.latitude, lng = location.coordinate.longitude
            let near = Self.cities.min { Self.distance($0, lat, lng) < Self.distance($1, lat, lng) }
            let name = near.map { Self.distance($0, lat, lng) < 40 ? $0.name : "My location" } ?? "My location"
            place = Place(name: name, lat: lat, lng: lng)
        case .failure(let failure):
            locationError = failure.message
        }
    }

    private func recompute() {
        guard let place else {
            today = []
            tomorrowFajr = nil
            timer?.invalidate()
            return
        }
        let now = Date()
        today = Self.compute(for: now, place: place, method: method, hanafi: hanafi)
        let tomorrow = Self.compute(for: now.addingTimeInterval(86_400), place: place, method: method, hanafi: hanafi)
        tomorrowFajr = tomorrow.first { $0.name == "Subuh" }
        tomorrowImsak = tomorrow.first { $0.name == "Imsak" }
        schedule()
        updateSoon()
    }

    // One timer for the next moment worth a notice: a reminder, a prayer time, or tomorrow's recompute.
    private func schedule() {
        timer?.invalidate()
        guard place != nil else { return }
        let now = Date()
        var events: [(date: Date, notice: Notice?, sound: Bool)] = []
        if alerts {
            for e in today + [tomorrowFajr].compactMap({ $0 }) where e.isPrayer {
                let time = e.time.formatted(date: .omitted, time: .shortened)
                events.append((e.time, Notice(icon: "moon.fill", color: Theme.accent, left: e.name, right: time,
                                              duration: 10, essential: true), true))
                if reminder > 0 {
                    events.append((e.time.addingTimeInterval(Double(-reminder * 60)),
                                   Notice(icon: "moon", color: Theme.amber, left: "\(e.name) in \(reminder) min",
                                          right: time, duration: 8, essential: true), false))
                }
            }
        }
        // Past midnight the schedule moves on to the next day.
        if let first = tomorrowFajr { events.append((first.time.addingTimeInterval(-3600), nil, false)) }
        guard let event = events.filter({ $0.date > now }).min(by: { $0.date < $1.date }) else { return }
        let t = Timer(fire: event.date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                if event.sound { NSSound(named: "Submarine")?.play() }
                if let notice = event.notice { self?.onNotice?(notice) }
                self?.recompute()
            }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // 15 minutes before each prayer; in Ramadan, 30 minutes before Imsak and before iftar too.
    private func updateSoon() {
        let now = Date()
        let ramadan = isRamadan
        let window: TimeInterval = ramadan ? 30 * 60 : 15 * 60
        let candidates = (today + [tomorrowFajr, tomorrowImsak].compactMap { $0 })
            .filter { $0.isPrayer || (ramadan && $0.name == "Imsak") }
        let next = candidates.filter { $0.time > now && $0.time.timeIntervalSince(now) <= window }.min { $0.time < $1.time }
        if next?.time != soon?.time || next?.name != soon?.name { soon = next }
    }

    nonisolated private static func distance(_ p: Place, _ lat: Double, _ lng: Double) -> Double {
        let dLat = (p.lat - lat) * 111, dLng = (p.lng - lng) * 111 * cos(lat * .pi / 180)
        return (dLat * dLat + dLng * dLng).squareRoot()
    }

    // The PrayTimes.org method: sun position from the Julian date, then the hour angle for each prayer's
    // sun altitude, computed in UTC and refined once with the first pass's times.
    nonisolated static func compute(for date: Date, place: Place, method: Method, hanafi: Bool) -> [Entry] {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let day = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let midnight = utc.date(from: day), let y = day.year, var m = day.month, let d = day.day else { return [] }
        var year = y
        if m <= 2 { year -= 1; m += 12 }
        let a = floor(Double(year) / 100), b = 2 - a + floor(a / 4)
        let jd = floor(365.25 * Double(year + 4716)) + floor(30.6001 * Double(m + 1)) + Double(d) + b - 1524.5
            - place.lng / (15 * 24)
        let lat = place.lat
        let rad = Double.pi / 180

        func fix(_ v: Double, _ r: Double) -> Double { let x = v.truncatingRemainder(dividingBy: r); return x < 0 ? x + r : x }
        func sun(_ t: Double) -> (decl: Double, eqt: Double) {
            let dd = jd + t - 2451545.0
            let g = fix(357.529 + 0.98560028 * dd, 360), q = fix(280.459 + 0.98564736 * dd, 360)
            let l = fix(q + 1.915 * sin(g * rad) + 0.020 * sin(2 * g * rad), 360)
            let e = 23.439 - 0.00000036 * dd
            let ra = fix(atan2(cos(e * rad) * sin(l * rad), cos(l * rad)) / rad / 15, 24)
            return (asin(sin(e * rad) * sin(l * rad)) / rad, q / 15 - ra)
        }
        func noon(_ t: Double) -> Double { fix(12 - sun(t).eqt, 24) }
        func angleTime(_ angle: Double, _ t: Double, ccw: Bool) -> Double {
            let decl = sun(t).decl
            let v = (-sin(angle * rad) - sin(decl * rad) * sin(lat * rad)) / (cos(decl * rad) * cos(lat * rad))
            let h = acos(min(max(v, -1), 1)) / rad / 15
            return noon(t) + (ccw ? -h : h)
        }
        func asr(_ t: Double) -> Double {
            let decl = sun(t).decl
            let angle = -atan(1 / ((hanafi ? 2 : 1) + tan(abs(lat - decl) * rad))) / rad
            return angleTime(angle, t, ccw: false)
        }
        func pass(_ t: [Double]) -> [Double] {
            let maghrib = angleTime(0.833, t[4] / 24, ccw: false)
            let isha = method.isha.minutes.map { maghrib + $0 / 60 }
                ?? angleTime(method.isha.angle ?? 17, t[5] / 24, ccw: false)
            return [angleTime(method.fajrAngle, t[0] / 24, ccw: true), angleTime(0.833, t[1] / 24, ccw: true),
                    noon(t[2] / 24), asr(t[3] / 24), maghrib, isha]
        }
        let times = pass(pass([5, 6, 12, 13, 18, 18]))
        let ihtiyat = method.ihtiyat / 60
        func at(_ hours: Double, _ extra: Double) -> Date {
            midnight.addingTimeInterval((hours - place.lng / 15 + extra) * 3600)
        }
        return [
            Entry(name: "Imsak", time: at(times[0], ihtiyat - 10.0 / 60), isPrayer: false),
            Entry(name: "Subuh", time: at(times[0], ihtiyat), isPrayer: true),
            Entry(name: "Terbit", time: at(times[1], -ihtiyat), isPrayer: false),
            Entry(name: "Dzuhur", time: at(times[2], ihtiyat), isPrayer: true),
            Entry(name: "Ashar", time: at(times[3], ihtiyat), isPrayer: true),
            Entry(name: "Maghrib", time: at(times[4], ihtiyat), isPrayer: true),
            Entry(name: "Isya", time: at(times[5], ihtiyat), isPrayer: true),
        ]
    }
}

struct LocationFailure: Error {
    let message: String
}

// One location fix through Core Location, asking for permission the first time.
private final class Locator: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var completion: ((Result<CLLocation, LocationFailure>) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func request(_ done: @escaping (Result<CLLocation, LocationFailure>) -> Void) {
        completion = done
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: fail("Location is off for Beanotch. Allow it in System Settings, or pick a city.")
        default: manager.requestLocation()
        }
    }

    private func fail(_ message: String) {
        completion?(.failure(LocationFailure(message: message)))
        completion = nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard completion != nil else { return }
        switch manager.authorizationStatus {
        case .notDetermined: break
        case .denied, .restricted: fail("Location is off for Beanotch. Allow it in System Settings, or pick a city.")
        default: manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        completion?(.success(location))
        completion = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        fail("macOS couldn't find this Mac's location. Pick a city instead.")
    }
}
