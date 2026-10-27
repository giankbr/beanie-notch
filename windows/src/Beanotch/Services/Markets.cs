using System.Globalization;
using System.Text.Json;

namespace Beanotch.Services;

// Exchange rates against the US dollar from open.er-api.com and the gold price from gold-api.com (both free, no key),
// kept for six hours, with yesterday's values remembered to show the change. As on the Mac.
public sealed class Rates(AppSettings settings)
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };
    public Dictionary<string, double> PerDollar { get; private set; } = [];
    public double? GoldOunce { get; private set; }
    private DateTime updated;
    private bool loading;

    public const double GramsPerOunce = 31.1034768;

    public static string Local
    {
        get
        {
            try { return new RegionInfo(CultureInfo.CurrentCulture.Name).ISOCurrencySymbol; }
            catch (Exception) { return "USD"; }
        }
    }

    public static string[] Watched =>
        [.. (Local == "IDR" ? new[] { "USD", "SGD", "EUR", "SAR", "JPY" } : ["USD", "EUR", "GBP", "JPY", "CNY", "CHF"]).Where(c => c != Local).Take(5)];

    public async Task RefreshAsync()
    {
        if (loading || DateTime.UtcNow - updated < TimeSpan.FromHours(6)) return;
        loading = true;
        try
        {
            var gold = Http.GetStringAsync("https://api.gold-api.com/price/XAU");
            using (var json = JsonDocument.Parse(await Http.GetStringAsync("https://open.er-api.com/v6/latest/USD")))
                PerDollar = json.RootElement.GetProperty("rates").EnumerateObject().ToDictionary(p => p.Name, p => p.Value.GetDouble());
            try
            {
                using var g = JsonDocument.Parse(await gold);
                GoldOunce = g.RootElement.GetProperty("price").GetDouble();
            }
            catch (Exception) { }
            updated = DateTime.UtcNow;
            Remember();
        }
        catch (Exception) { }
        finally { loading = false; }
    }

    public double? Convert(double amount, string from, string to) =>
        PerDollar.TryGetValue(from, out var a) && PerDollar.TryGetValue(to, out var b) && a > 0 ? amount / a * b : null;

    public double? Value(string code) => Convert(1, code, Local);

    public double? GoldGram => GoldOunce is { } o ? Convert(o / GramsPerOunce, "USD", Local) : null;

    public double? Change(string key, double? now) =>
        now is { } v && settings.RatesPrevious.TryGetValue(key, out var before) && before > 0 ? v / before - 1 : null;

    private void Remember()
    {
        var day = DateTime.Now.ToString("yyyy-MM-dd");
        var values = Watched.Select(c => (c, Value(c))).Where(p => p.Item2 is not null).ToDictionary(p => p.c, p => p.Item2!.Value);
        if (GoldGram is { } gram) values["gold"] = gram;
        if (settings.RatesDay != day)
        {
            if (settings.RatesToday.Count > 0) settings.RatesPrevious = settings.RatesToday;
            settings.RatesDay = day;
        }
        settings.RatesToday = values;
        settings.Save();
    }

    public static string Format(double amount, string currency)
    {
        var digits = amount >= 1000 || currency is "IDR" or "JPY" ? 0 : 2;
        var symbol = currency switch { "IDR" => "Rp", "USD" => "$", "EUR" => "€", "GBP" => "£", "JPY" => "¥", _ => currency + " " };
        var number = amount.ToString("N" + digits, currency == "IDR" ? CultureInfo.GetCultureInfo("id-ID") : CultureInfo.CurrentCulture);
        return currency == "IDR" ? $"Rp {number}" : symbol + number;
    }
}

// Earthquakes from BMKG for a place in Indonesia: the latest quake, read every minute. One within 300 km, M6 or more
// anywhere in the country, or one with a tsunami risk raises a red notice, as on the Mac.
public sealed class Quakes(AppSettings settings)
{
    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };
    public event Action<Notice>? Notice;

    public static bool InIndonesia(Core.Place p) => p.Lat is >= -11.5 and <= 6.5 && p.Lng is >= 94.5 and <= 141.5;

    public static double Distance(Core.Place p, double lat, double lng)
    {
        double dLat = (p.Lat - lat) * 111, dLng = (p.Lng - lng) * 111 * Math.Cos(lat * Math.PI / 180);
        return Math.Sqrt(dLat * dLat + dLng * dLng);
    }

    public async Task CheckAsync()
    {
        var place = settings.Place;
        if (!settings.QuakeAlerts || !InIndonesia(place)) return;
        try
        {
            using var json = JsonDocument.Parse(await Http.GetStringAsync("https://data.bmkg.go.id/DataMKG/TEWS/autogempa.json"));
            var g = json.RootElement.GetProperty("Infogempa").GetProperty("gempa");
            var id = g.GetProperty("DateTime").GetString() ?? "";
            if (id == settings.QuakeSeen) return;
            var first = settings.QuakeSeen.Length == 0;
            settings.QuakeSeen = id;
            settings.Save();
            if (first) return;
            var at = (g.GetProperty("Coordinates").GetString() ?? "").Split(',').Select(v => double.Parse(v.Trim(), CultureInfo.InvariantCulture)).ToArray();
            var magnitude = double.Parse(g.GetProperty("Magnitude").GetString() ?? "0", CultureInfo.InvariantCulture);
            var potential = (g.TryGetProperty("Potensi", out var p) ? p.GetString() ?? "" : "").ToLowerInvariant();
            var tsunami = potential.Contains("tsunami") && !potential.Contains("tidak berpotensi");
            var km = Distance(place, at[0], at[1]);
            if (km > 300 && magnitude < 6 && !tsunami) return;
            var depth = g.TryGetProperty("Kedalaman", out var d) ? d.GetString() : "?";
            var map = g.TryGetProperty("Shakemap", out var s) ? new Uri("https://data.bmkg.go.id/DataMKG/TEWS/" + s.GetString()) : null;
            Notice?.Invoke(new Notice("", Ui.Theme.Red, tsunami ? $"Tsunami risk · M{magnitude.ToString("0.0", CultureInfo.InvariantCulture)}"
                                      : $"Earthquake M{magnitude.ToString("0.0", CultureInfo.InvariantCulture)}",
                                      $"{Math.Round(km)} km away · {depth} deep", TimeSpan.FromSeconds(20), Essential: true, Open: map));
        }
        catch (Exception) { }
    }
}
