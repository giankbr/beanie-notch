using System.Globalization;
using System.Net.Http.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace Beanotch.Core;

public sealed record LyricLine(TimeSpan Time, string Text);

// Synced lyrics from LRCLIB: free, no key, and only the song's title, artist and length are sent.
public sealed partial class Lyrics(HttpClient http)
{
    sealed record Response([property: JsonPropertyName("syncedLyrics")] string? Synced);

    public async Task<IReadOnlyList<LyricLine>> FetchAsync(string title, string artist, TimeSpan duration, CancellationToken cancel = default)
    {
        var query = $"track_name={Uri.EscapeDataString(title)}&artist_name={Uri.EscapeDataString(artist)}";
        if (duration > TimeSpan.Zero) query += $"&duration={(int)duration.TotalSeconds}";
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, $"https://lrclib.net/api/get?{query}");
            request.Headers.UserAgent.ParseAdd("Beanotch-Windows (https://github.com/giankbr/beanie-notch)");
            using var response = await http.SendAsync(request, cancel);
            if (!response.IsSuccessStatusCode) return [];
            var body = await response.Content.ReadFromJsonAsync<Response>(cancel);
            return body?.Synced is string synced ? Parse(synced) : [];
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException)
        {
            return [];
        }
    }

    [GeneratedRegex(@"\[(\d+):(\d+(?:\.\d+)?)\]")]
    private static partial Regex Stamp();

    // "[01:02.50]Line" — a line can carry several stamps when it repeats.
    public static IReadOnlyList<LyricLine> Parse(string lrc)
    {
        var lines = new List<LyricLine>();
        foreach (var raw in lrc.Split('\n'))
        {
            var stamps = Stamp().Matches(raw);
            if (stamps.Count == 0) continue;
            var text = raw[(stamps[^1].Index + stamps[^1].Length)..].Trim();
            foreach (Match s in stamps)
            {
                var seconds = int.Parse(s.Groups[1].Value, CultureInfo.InvariantCulture) * 60
                              + double.Parse(s.Groups[2].Value, CultureInfo.InvariantCulture);
                lines.Add(new LyricLine(TimeSpan.FromSeconds(seconds), text));
            }
        }
        lines.Sort((x, y) => x.Time.CompareTo(y.Time));
        return lines;
    }

    // The line being sung at this position, or null before the first one.
    public static LyricLine? At(IReadOnlyList<LyricLine> lines, TimeSpan position)
    {
        LyricLine? current = null;
        foreach (var line in lines)
        {
            if (line.Time > position) break;
            current = line;
        }
        return current;
    }
}
