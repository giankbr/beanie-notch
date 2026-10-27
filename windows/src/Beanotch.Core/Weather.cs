using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json.Serialization;

namespace Beanotch.Core;

public sealed record WeatherHour(DateTimeOffset Time, double Temp, int Code);

public sealed record WeatherReport(double Temp, int Code, double High, double Low, IReadOnlyList<WeatherHour> Hours);

public sealed record OpenMeteoResponse(
    [property: JsonPropertyName("utc_offset_seconds")] int Offset,
    [property: JsonPropertyName("current")] OpenMeteoCurrent Current,
    [property: JsonPropertyName("hourly")] OpenMeteoHourly Hourly,
    [property: JsonPropertyName("daily")] OpenMeteoDaily Daily);

public sealed record OpenMeteoCurrent([property: JsonPropertyName("temperature_2m")] double Temp, [property: JsonPropertyName("weather_code")] int Code);

public sealed record OpenMeteoHourly(
    [property: JsonPropertyName("time")] string[] Time,
    [property: JsonPropertyName("temperature_2m")] double[] Temp,
    [property: JsonPropertyName("weather_code")] int[] Code);

public sealed record OpenMeteoDaily([property: JsonPropertyName("temperature_2m_max")] double[] High, [property: JsonPropertyName("temperature_2m_min")] double[] Low);

[JsonSerializable(typeof(OpenMeteoResponse))]
internal sealed partial class WeatherJson : JsonSerializerContext;

// Open-Meteo, as on the Mac: no account and no key; only the place's coordinates are sent.
public static class Weather
{
    public static async Task<WeatherReport?> FetchAsync(HttpClient http, double lat, double lng, CancellationToken cancel = default)
    {
        var url = FormattableString.Invariant($"https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lng}")
            + "&current=temperature_2m,weather_code&hourly=temperature_2m,weather_code"
            + "&daily=temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=2";
        try
        {
            var r = await http.GetFromJsonAsync(url, WeatherJson.Default.OpenMeteoResponse, cancel);
            return r is null ? null : Parse(r, DateTimeOffset.Now);
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException)
        {
            return null;
        }
    }

    public static WeatherReport Parse(OpenMeteoResponse r, DateTimeOffset now)
    {
        var offset = TimeSpan.FromSeconds(r.Offset);
        var hours = new List<WeatherHour>();
        for (var i = 0; i < Math.Min(r.Hourly.Time.Length, Math.Min(r.Hourly.Temp.Length, r.Hourly.Code.Length)); i++)
        {
            if (!DateTime.TryParseExact(r.Hourly.Time[i], "yyyy-MM-dd'T'HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var local)) continue;
            var time = new DateTimeOffset(local, offset);
            if (time > now) hours.Add(new WeatherHour(time, r.Hourly.Temp[i], r.Hourly.Code[i]));
            if (hours.Count == 5) break;
        }
        return new WeatherReport(r.Current.Temp, r.Current.Code, r.Daily.High.FirstOrDefault(), r.Daily.Low.FirstOrDefault(), hours);
    }

    // WMO weather codes, as Open-Meteo reports them.
    public static string Describe(int code) => code switch
    {
        0 => "Clear",
        1 or 2 => "Partly cloudy",
        3 => "Cloudy",
        45 or 48 => "Fog",
        >= 51 and <= 57 => "Drizzle",
        >= 61 and <= 67 => "Rain",
        >= 80 and <= 82 => "Showers",
        (>= 71 and <= 77) or 85 or 86 => "Snow",
        >= 95 and <= 99 => "Thunderstorm",
        _ => "—",
    };
}
