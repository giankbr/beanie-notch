import AppKit

// A second look at text as it's copied: a one-time code inside a message, a price in another currency, an address
// or a parcel's tracking number each get a short notice in the notch, with something to do about it.
@MainActor
final class SmartCopy {
    var enabled = true
    var onNotice: ((Notice) -> Void)?
    private let rates: Rates

    init(rates: Rates) { self.rates = rates }

    func check(_ copied: String) {
        guard enabled else { return }
        let text = copied.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count < 400 else { return }
        if let code = Self.code(in: text) {
            // The code alone goes on the clipboard, ready to paste; the message stays in the history.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(code, forType: .string)
            onNotice?(Notice(icon: "lock.fill", color: Theme.accent, left: "Code copied", right: code, duration: 8))
        } else if let (amount, currency) = Self.price(in: text), currency != Rates.local {
            Task {
                await rates.refresh()
                guard let value = rates.convert(amount, from: currency, to: Rates.local) else { return }
                onNotice?(Notice(icon: "dollarsign.arrow.circlepath", color: Theme.accent2,
                                 left: Rates.format(amount, currency), right: "≈ " + Rates.format(value, Rates.local), duration: 8))
            }
        } else if let tracking = Self.tracking(in: text) {
            let indonesia = Locale.current.region?.identifier == "ID"
            let link = indonesia ? "https://cekresi.com/?noresi=\(tracking)" : "https://parcelsapp.com/en/tracking/\(tracking)"
            onNotice?(Notice(icon: "shippingbox.fill", color: Theme.amber, left: "Parcel", right: "Click to track \(tracking)",
                             duration: 8, open: URL(string: link)))
        } else if Self.isAddress(text), let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            onNotice?(Notice(icon: "map.fill", color: Theme.good, left: "Address", right: "Click to open in Maps",
                             duration: 8, open: URL(string: "https://maps.apple.com/?q=\(query)")))
        }
    }

    // MARK: Codes

    private static let codeWords = try! NSRegularExpression(
        pattern: #"\b(code|kode|otp|verification|verifikasi|passcode|pin|token|sandi)\b"#, options: .caseInsensitive)
    private static let codeDigits = try! NSRegularExpression(pattern: #"(?<![\d.,:/-])(\d{3}[ -]\d{3}|\d{4,8})(?!\d|[.,:/-]\d)"#)

    // A short message that says it carries a code, and the code in it. A bare code was copied on purpose already.
    static func code(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard text.count > 8, codeWords.firstMatch(in: text, range: range) != nil,
              let match = codeDigits.firstMatch(in: text, range: range),
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return text[r].filter(\.isNumber)
    }

    // MARK: Prices

    private static let symbols: [(String, String)] = [
        ("US$", "USD"), ("S$", "SGD"), ("A$", "AUD"), ("HK$", "HKD"), ("NT$", "TWD"), ("C$", "CAD"), ("RM", "MYR"), ("Rp", "IDR"),
        ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"), ("₹", "INR"), ("₩", "KRW"), ("฿", "THB"), ("₱", "PHP"), ("₫", "VND"),
    ]
    private static let codes = ["USD", "EUR", "GBP", "JPY", "SGD", "MYR", "IDR", "AUD", "CNY", "HKD", "INR", "KRW", "THB", "PHP",
                                "VND", "CAD", "CHF", "SAR", "AED", "TWD", "NZD"]

    // "$25", "Rp 50.000", "EUR 1.234,50", "120 SGD": a price and nothing much else.
    static func price(in text: String) -> (Double, String)? {
        guard text.count <= 30 else { return nil }
        var rest = text.replacingOccurrences(of: "\u{00A0}", with: " ")
        var currency: String?
        for code in codes where rest.uppercased().hasPrefix(code) || rest.uppercased().hasSuffix(code) {
            currency = code
            rest = rest.uppercased().replacingOccurrences(of: code, with: "")
            break
        }
        if currency == nil {
            for (symbol, code) in symbols where rest.hasPrefix(symbol) || rest.hasSuffix(symbol) {
                currency = code
                rest = rest.replacingOccurrences(of: symbol, with: "")
                break
            }
        }
        rest = rest.trimmingCharacters(in: CharacterSet(charactersIn: " .:"))
        guard let currency, !rest.isEmpty, rest.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," }),
              let amount = number(rest), amount > 0 else { return nil }
        return (amount, currency)
    }

    // Reads both 1,234.56 and 1.234,56; a lone separator before exactly two digits is the decimal point.
    static func number(_ s: String) -> Double? {
        let lastDot = s.lastIndex(of: "."), lastComma = s.lastIndex(of: ",")
        var decimal: Character?
        if let d = lastDot, let c = lastComma { decimal = d > c ? "." : "," }
        else if let sep = lastDot ?? lastComma {
            let char = s[sep]
            if s.filter({ $0 == char }).count == 1, s.distance(from: sep, to: s.endIndex) - 1 <= 2 { decimal = char }
        }
        var digits = ""
        for ch in s {
            if ch.isNumber { digits.append(ch) } else if ch == decimal { digits.append(".") }
        }
        return Double(digits)
    }

    // MARK: Parcels and addresses

    private static let trackingPatterns = [
        #"^[A-Z]{2}\d{9}[A-Z]{2}$"#,              // international post (UPU)
        #"^(JP|JD|JX|JO|JT)\d{10,12}$"#,          // J&T
        #"^00\d{10}$"#,                            // SiCepat
        #"^(SPXID|IDS)\d{9,14}[A-Z]?$"#,          // Shopee Xpress
        #"^(CGK|SUB|BDO|JOG|MES|DPS|UPG|SRG|BPN|PLM)[A-Z0-9]{8,16}$"#, // JNE
        #"^(LXAD|LXST|LEX)[A-Z0-9-]{8,20}$"#,     // Lazada
        #"^1Z[0-9A-Z]{16}$"#,                      // UPS
    ].map { try! NSRegularExpression(pattern: $0) }

    static func tracking(in text: String) -> String? {
        let candidate = text.uppercased().replacingOccurrences(of: " ", with: "")
        let range = NSRange(candidate.startIndex..., in: candidate)
        return trackingPatterns.contains { $0.firstMatch(in: candidate, range: range) != nil } ? candidate : nil
    }

    private static let addresses = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.address.rawValue)

    // An address that is most of what was copied, not one buried in a long text.
    static func isAddress(_ text: String) -> Bool {
        guard text.count >= 12 else { return false }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = addresses.firstMatch(in: text, range: range) else { return false }
        return Double(match.range.length) >= Double(range.length) * 0.6
    }
}
