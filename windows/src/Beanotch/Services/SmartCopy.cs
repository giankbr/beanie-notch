using System.Text.RegularExpressions;

namespace Beanotch.Services;

// A second look at text as it's copied: a one-time code inside a message, a price in another currency, an address or
// a parcel's tracking number each get a short notice in the island, with something to do about it. As on the Mac.
public sealed partial class SmartCopy(AppSettings settings, Rates rates)
{
    public event Action<Notice>? Notice;
    // Puts text on the clipboard without it counting as a new copy.
    public Action<string>? Copy;

    public void Check(string copied)
    {
        if (!settings.SmartCopy) return;
        var text = copied.Trim();
        if (text.Length == 0 || text.Length >= 400) return;
        if (Code(text) is { } code)
        {
            Copy?.Invoke(code);
            Notice?.Invoke(new Notice("", Ui.Theme.Accent, "Code copied", code, TimeSpan.FromSeconds(8)));
        }
        else if (Price(text) is { } price && price.Currency != Rates.Local)
        {
            _ = Convert(price.Amount, price.Currency);
        }
        else if (Tracking(text) is { } tracking)
        {
            var link = Rates.Local == "IDR" ? $"https://cekresi.com/?noresi={tracking}" : $"https://parcelsapp.com/en/tracking/{tracking}";
            Notice?.Invoke(new Notice("", Ui.Theme.Amber, "Parcel", $"Click to track {tracking}", TimeSpan.FromSeconds(8), Open: new Uri(link)));
        }
        else if (IsAddress(text))
        {
            Notice?.Invoke(new Notice("", Ui.Theme.Good, "Address", "Click to open in Maps", TimeSpan.FromSeconds(8),
                                      Open: new Uri("https://www.google.com/maps/search/?api=1&query=" + Uri.EscapeDataString(text))));
        }
    }

    private async Task Convert(double amount, string currency)
    {
        await rates.RefreshAsync();
        if (rates.Convert(amount, currency, Rates.Local) is not { } value) return;
        Notice?.Invoke(new Notice("", Ui.Theme.Accent2, Rates.Format(amount, currency), "≈ " + Rates.Format(value, Rates.Local), TimeSpan.FromSeconds(8)));
    }

    [GeneratedRegex(@"\b(code|kode|otp|verification|verifikasi|passcode|pin|token|sandi)\b", RegexOptions.IgnoreCase)]
    private static partial Regex CodeWords();

    [GeneratedRegex(@"(?<![\d.,:/-])(\d{3}[ -]\d{3}|\d{4,8})(?!\d|[.,:/-]\d)")]
    private static partial Regex CodeDigits();

    public static string? Code(string text)
    {
        if (text.Length <= 8 || !CodeWords().IsMatch(text)) return null;
        var m = CodeDigits().Match(text);
        return m.Success ? new string([.. m.Groups[1].Value.Where(char.IsDigit)]) : null;
    }

    private static readonly (string Symbol, string Code)[] Symbols =
    [
        ("US$", "USD"), ("S$", "SGD"), ("A$", "AUD"), ("HK$", "HKD"), ("NT$", "TWD"), ("C$", "CAD"), ("RM", "MYR"), ("Rp", "IDR"),
        ("$", "USD"), ("€", "EUR"), ("£", "GBP"), ("¥", "JPY"), ("₹", "INR"), ("₩", "KRW"), ("฿", "THB"), ("₱", "PHP"), ("₫", "VND"),
    ];
    private static readonly string[] Codes = ["USD", "EUR", "GBP", "JPY", "SGD", "MYR", "IDR", "AUD", "CNY", "HKD", "INR", "KRW", "THB",
                                              "PHP", "VND", "CAD", "CHF", "SAR", "AED", "TWD", "NZD"];

    public static (double Amount, string Currency)? Price(string text)
    {
        if (text.Length > 30) return null;
        var rest = text.Replace(' ', ' ');
        string? currency = null;
        foreach (var code in Codes)
            if (rest.ToUpperInvariant().StartsWith(code) || rest.ToUpperInvariant().EndsWith(code))
            {
                currency = code;
                rest = rest.ToUpperInvariant().Replace(code, "");
                break;
            }
        if (currency is null)
            foreach (var (symbol, code) in Symbols)
                if (rest.StartsWith(symbol) || rest.EndsWith(symbol))
                {
                    currency = code;
                    rest = rest.Replace(symbol, "");
                    break;
                }
        rest = rest.Trim(' ', '.', ':');
        if (currency is null || rest.Length == 0 || !rest.All(c => char.IsDigit(c) || c is '.' or ',')) return null;
        return Number(rest) is { } amount && amount > 0 ? (amount, currency) : null;
    }

    // Reads both 1,234.56 and 1.234,56; a lone separator before at most two digits is the decimal point.
    public static double? Number(string s)
    {
        int dot = s.LastIndexOf('.'), comma = s.LastIndexOf(',');
        char? decimalMark = null;
        if (dot >= 0 && comma >= 0) decimalMark = dot > comma ? '.' : ',';
        else if (Math.Max(dot, comma) is var sep && sep >= 0 && s.Count(c => c == s[sep]) == 1 && s.Length - sep - 1 <= 2) decimalMark = s[sep];
        var digits = string.Concat(s.Select(c => char.IsDigit(c) ? c.ToString() : c == decimalMark ? "." : ""));
        return double.TryParse(digits, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var v) ? v : null;
    }

    private static readonly Regex[] TrackingPatterns =
    [
        new(@"^[A-Z]{2}\d{9}[A-Z]{2}$"), new(@"^(JP|JD|JX|JO|JT)\d{10,12}$"), new(@"^00\d{10}$"), new(@"^(SPXID|IDS)\d{9,14}[A-Z]?$"),
        new(@"^(CGK|SUB|BDO|JOG|MES|DPS|UPG|SRG|BPN|PLM)[A-Z0-9]{8,16}$"), new(@"^(LXAD|LXST|LEX)[A-Z0-9-]{8,20}$"), new(@"^1Z[0-9A-Z]{16}$"),
    ];

    public static string? Tracking(string text)
    {
        var candidate = text.ToUpperInvariant().Replace(" ", "");
        return TrackingPatterns.Any(p => p.IsMatch(candidate)) ? candidate : null;
    }

    [GeneratedRegex(@"\b(jl\.?|jalan|gg\.?|gang|street|st\.|road|rd\.|avenue|ave\.?|blvd|lane)\s", RegexOptions.IgnoreCase)]
    private static partial Regex Street();

    // Windows has no address detector: a street word and a number, in something address-sized.
    public static bool IsAddress(string text) =>
        text.Length is >= 12 and <= 200 && !text.Contains('\n') && Street().IsMatch(text + " ") && text.Any(char.IsDigit);
}
