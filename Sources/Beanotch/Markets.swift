import Foundation

// Exchange rates against the US dollar, from open.er-api.com (free, no key, updated daily), the gold price from
// gold-api.com (free, no key) and, in Indonesia, Pertamina's fuel prices for the province from the API behind
// MyPertamina's price page, kept for six hours. Each day's values are remembered so the next day can show the change.
@MainActor
final class Rates: ObservableObject {
    @Published private(set) var perDollar: [String: Double] = [:]
    @Published private(set) var goldOunce: Double?
    // Pertamina's prices per litre in the province, by product ("PERTALITE").
    @Published private(set) var fuel: [String: Double] = [:]
    // The city the prayer times are for, to pick the province.
    var city: (() -> String?)?
    @Published private(set) var updated: Date?
    private var loading = false
    private var previous: [String: Double] = UserDefaults.standard.dictionary(forKey: "ratesPrevious") as? [String: Double] ?? [:]

    static let gramsPerOunce = 31.1034768

    // The currencies worth watching from here: Indonesia's neighbours and the riyal for umrah, or the majors.
    static var watched: [String] {
        // In Indonesia three currencies leave room for gold and fuel.
        let list = local == "IDR" ? ["USD", "SGD", "SAR"] : ["USD", "EUR", "GBP", "JPY", "CNY", "CHF"]
        return Array(list.filter { $0 != local }.prefix(5))
    }

    // One unit of `code` in the local currency.
    func value(of code: String) -> Double? {
        convert(1, from: code, to: Self.local)
    }

    // A gram of gold in the local currency.
    var goldGram: Double? {
        guard let goldOunce else { return nil }
        return convert(goldOunce / Self.gramsPerOunce, from: "USD", to: Self.local)
    }

    // Since the day before, as a share: 0.012 is up 1.2%.
    func change(_ key: String, now: Double?) -> Double? {
        guard let now, let before = previous[key], before > 0 else { return nil }
        return now / before - 1
    }

    private func remember() {
        let d = UserDefaults.standard
        let day = Date().formatted(.iso8601.year().month().day())
        var values = Dictionary(uniqueKeysWithValues: Self.watched.compactMap { code in value(of: code).map { (code, $0) } })
        if let goldGram { values["gold"] = goldGram }
        for (product, price) in fuel { values[product] = price }
        if d.string(forKey: "ratesDay") != day {
            if let last = d.dictionary(forKey: "ratesToday") as? [String: Double] {
                previous = last
                d.set(last, forKey: "ratesPrevious")
            }
            d.set(day, forKey: "ratesDay")
        }
        d.set(values, forKey: "ratesToday")
    }

    // The currency of the Mac's region: what amounts are converted into.
    static var local: String { Locale.current.currency?.identifier ?? "USD" }

    func refresh() async {
        if let updated, Date().timeIntervalSince(updated) < 6 * 3600 { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        async let gold = try? URLSession.shared.data(from: URL(string: "https://api.gold-api.com/price/XAU")!)
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "https://open.er-api.com/v6/latest/USD")!),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = json["rates"] as? [String: Double] else { return }
        if let (data, _) = await gold, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            goldOunce = json["price"] as? Double
        }
        if Self.local == "IDR" { fuel = await Self.fuelPrices(province: Self.province(for: city?() ?? "Jakarta")) }
        perDollar = rates
        updated = Date()
        remember()
    }

    static let fuels = ["PERTALITE", "PERTAMAX"]

    private static func fuelPrices(province: String) async -> [String: Double] {
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "https://api.web.mypertamina.id/price?limit=60&page=1")!),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rows = (json["data"] as? [String: Any])?["data"] as? [[String: Any]],
              let row = rows.first(where: { ($0["province"] as? String)?.hasSuffix(province) == true }),
              let list = row["list_price"] as? [[String: Any]] else { return [:] }
        var prices: [String: Double] = [:]
        for item in list {
            // Prices come as "16300" or "Rp 10.000"; 0 means not sold there.
            guard let product = item["product"] as? String, let raw = item["price"] as? String,
                  let value = Double(raw.filter(\.isNumber)), value > 0 else { continue }
            prices[product] = value
        }
        return prices
    }

    // Pertamina lists prices by province, and Batam on its own as a free trade zone.
    static func province(for city: String) -> String {
        switch city {
        case "Jakarta": "DKI Jakarta"
        case "Bogor", "Depok", "Bekasi", "Bandung", "Cirebon": "Jawa Barat"
        case "Tangerang": "Banten"
        case "Semarang", "Surakarta": "Jawa Tengah"
        case "Yogyakarta": "DI Yogyakarta"
        case "Surabaya", "Malang": "Jawa Timur"
        case "Denpasar": "Bali"
        case "Mataram": "Nusa Tenggara Barat"
        case "Kupang": "Nusa Tenggara Timur"
        case "Banda Aceh": "Aceh"
        case "Medan": "Sumatera Utara"
        case "Padang": "Sumatera Barat"
        case "Pekanbaru": "Riau"
        case "Batam": "(FTZ) Batam"
        case "Jambi": "Jambi"
        case "Palembang": "Sumatera Selatan"
        case "Bengkulu": "Bengkulu"
        case "Bandar Lampung": "Lampung"
        case "Pontianak": "Kalimantan Barat"
        case "Banjarmasin": "Kalimantan Selatan"
        case "Balikpapan", "Samarinda": "Kalimantan Timur"
        case "Makassar": "Sulawesi Selatan"
        case "Palu": "Sulawesi Tengah"
        case "Kendari": "Sulawesi Tenggara"
        case "Manado": "Sulawesi Utara"
        case "Ambon": "Maluku"
        case "Jayapura": "Papua"
        default: "DKI Jakarta"
        }
    }

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let a = perDollar[from], let b = perDollar[to], a > 0 else { return nil }
        return amount / a * b
    }

    static func format(_ amount: Double, _ currency: String) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(amount >= 1000 || currency == "IDR" || currency == "JPY" ? 0 : 2)))
    }
}
