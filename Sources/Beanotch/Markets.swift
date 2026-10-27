import Foundation

// Exchange rates against the US dollar, from open.er-api.com (free, no key, updated daily), kept for six hours.
@MainActor
final class Rates: ObservableObject {
    @Published private(set) var perDollar: [String: Double] = [:]
    @Published private(set) var updated: Date?
    private var loading = false

    // The currency of the Mac's region: what amounts are converted into.
    static var local: String { Locale.current.currency?.identifier ?? "USD" }

    func refresh() async {
        if let updated, Date().timeIntervalSince(updated) < 6 * 3600 { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        guard let (data, _) = try? await URLSession.shared.data(from: URL(string: "https://open.er-api.com/v6/latest/USD")!),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rates = json["rates"] as? [String: Double] else { return }
        perDollar = rates
        updated = Date()
    }

    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let a = perDollar[from], let b = perDollar[to], a > 0 else { return nil }
        return amount / a * b
    }

    static func format(_ amount: Double, _ currency: String) -> String {
        amount.formatted(.currency(code: currency).precision(.fractionLength(amount >= 1000 || currency == "IDR" || currency == "JPY" ? 0 : 2)))
    }
}
