import Foundation

// Exchange rates against the US dollar, from open.er-api.com (free, no key, updated daily), and the gold price from
// gold-api.com (free, no key), kept for six hours. Each day's values are remembered so the next day can show the change.
@MainActor
final class Rates: ObservableObject {
    @Published private(set) var perDollar: [String: Double] = [:]
    @Published private(set) var goldOunce: Double?
    @Published private(set) var updated: Date?
    private var loading = false
    private var previous: [String: Double] = UserDefaults.standard.dictionary(forKey: "ratesPrevious") as? [String: Double] ?? [:]

    static let gramsPerOunce = 31.1034768

    // The currencies worth watching from here: Indonesia's neighbours and the riyal for umrah, or the majors.
    static var watched: [String] {
        let list = local == "IDR" ? ["USD", "SGD", "EUR", "SAR", "JPY"] : ["USD", "EUR", "GBP", "JPY", "CNY", "CHF"]
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
        perDollar = rates
        updated = Date()
        remember()
    }

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let a = perDollar[from], let b = perDollar[to], a > 0 else { return nil }
        return amount / a * b
    }

    static func format(_ amount: Double, _ currency: String) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(amount >= 1000 || currency == "IDR" || currency == "JPY" ? 0 : 2)))
    }
}
