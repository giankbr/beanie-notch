using System.Globalization;
using System.Text.RegularExpressions;

namespace Beanotch.Core;

public sealed record CalendarEvent(string Title, DateTimeOffset Start, DateTimeOffset End, bool AllDay, string? Location, string? Link);

// Windows doesn't let an unpackaged app read the system calendar, so Beanotch for Windows reads a calendar's secret
// iCal address instead (Google Calendar and Outlook both offer one). Covers what invitations use: time zones,
// all-day events, simple repeats (daily, weekly on given days, monthly, yearly), exceptions and cancellations.
public static partial class Calendar
{
    public static async Task<IReadOnlyList<CalendarEvent>> FetchAsync(HttpClient http, string url, DateTimeOffset from, DateTimeOffset to,
                                                                    CancellationToken cancel = default)
    {
        if (url.StartsWith("webcal://", StringComparison.OrdinalIgnoreCase)) url = "https://" + url[9..];
        try { return Parse(await http.GetStringAsync(url, cancel), from, to); }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or UriFormatException or InvalidOperationException) { return []; }
    }

    private sealed class Raw
    {
        public string Uid = "", Title = "", Location = "", Description = "", Url = "", Rule = "", Status = "";
        public DateTimeOffset? Start, End, RecurrenceId;
        public TimeSpan? Duration;
        public bool AllDay;
        public readonly List<DateTimeOffset> Excluded = [];
    }

    public static IReadOnlyList<CalendarEvent> Parse(string ics, DateTimeOffset from, DateTimeOffset to)
    {
        var raws = new List<Raw>();
        Raw? current = null;
        foreach (var line in Unfold(ics))
        {
            if (line == "BEGIN:VEVENT") { current = new Raw(); continue; }
            if (line == "END:VEVENT") { if (current?.Start is not null) raws.Add(current); current = null; continue; }
            if (current is null) continue;
            var colon = line.IndexOf(':');
            if (colon < 0) continue;
            var head = line[..colon];
            var value = line[(colon + 1)..];
            var parts = head.Split(';');
            var name = parts[0].ToUpperInvariant();
            var tzid = parts.Skip(1).FirstOrDefault(p => p.StartsWith("TZID=", StringComparison.OrdinalIgnoreCase))?[5..].Trim('"');
            switch (name)
            {
                case "UID": current.Uid = value; break;
                case "SUMMARY": current.Title = Unescape(value); break;
                case "LOCATION": current.Location = Unescape(value); break;
                case "DESCRIPTION": current.Description = Unescape(value); break;
                case "URL": current.Url = value; break;
                case "RRULE": current.Rule = value; break;
                case "STATUS": current.Status = value.ToUpperInvariant(); break;
                case "DTSTART":
                    current.Start = Time(value, tzid, out var allDay);
                    current.AllDay = allDay;
                    break;
                case "DTEND": current.End = Time(value, tzid, out _); break;
                case "DURATION": current.Duration = Duration(value); break;
                case "RECURRENCE-ID": current.RecurrenceId = Time(value, tzid, out _); break;
                case "EXDATE":
                    foreach (var v in value.Split(',')) if (Time(v, tzid, out _) is { } ex) current.Excluded.Add(ex);
                    break;
            }
        }

        // A changed occurrence (RECURRENCE-ID) replaces the one its series would have produced.
        var moved = raws.Where(r => r.RecurrenceId is not null).Select(r => (r.Uid, r.RecurrenceId!.Value)).ToHashSet();
        var events = new List<CalendarEvent>();
        foreach (var raw in raws)
        {
            if (raw.Status == "CANCELLED") continue;
            var start = raw.Start!.Value;
            var length = raw.End is { } end ? end - start : raw.Duration ?? (raw.AllDay ? TimeSpan.FromDays(1) : TimeSpan.Zero);
            var link = MeetingLink(string.Join(" ", raw.Url, raw.Location, raw.Description));
            var location = raw.Location.Length > 0 ? raw.Location : null;
            var starts = raw.Rule.Length > 0 && raw.RecurrenceId is null ? Expand(start, raw.Rule, from - length, to) : [start];
            foreach (var s in starts)
            {
                if (raw.Excluded.Contains(s) || (raw.Rule.Length > 0 && moved.Contains((raw.Uid, s)))) continue;
                if (s + length <= from || s >= to) continue;
                events.Add(new CalendarEvent(raw.Title.Length > 0 ? raw.Title : "Busy", s, s + length, raw.AllDay, location, link));
            }
        }
        events.Sort((a, b) => a.Start.CompareTo(b.Start));
        return events;
    }

    private static IEnumerable<string> Unfold(string ics)
    {
        string? pending = null;
        foreach (var raw in ics.Replace("\r\n", "\n").Split('\n'))
        {
            if (raw.Length > 0 && (raw[0] == ' ' || raw[0] == '\t')) { pending += raw[1..]; continue; }
            if (pending is not null) yield return pending;
            pending = raw;
        }
        if (pending is not null) yield return pending;
    }

    private static string Unescape(string v) => v.Replace("\\n", "\n").Replace("\\N", "\n").Replace("\\,", ",").Replace("\\;", ";").Replace("\\\\", "\\");

    private static DateTimeOffset? Time(string value, string? tzid, out bool allDay)
    {
        allDay = false;
        value = value.Trim();
        if (value.Length == 8 && DateTime.TryParseExact(value, "yyyyMMdd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var day))
        {
            allDay = true;
            return new DateTimeOffset(day, TimeZoneInfo.Local.GetUtcOffset(day));
        }
        var utc = value.EndsWith('Z');
        if (!DateTime.TryParseExact(value.TrimEnd('Z'), "yyyyMMdd'T'HHmmss", CultureInfo.InvariantCulture, DateTimeStyles.None, out var t)) return null;
        if (utc) return new DateTimeOffset(DateTime.SpecifyKind(t, DateTimeKind.Utc));
        var zone = Zone(tzid) ?? TimeZoneInfo.Local;
        return new DateTimeOffset(t, zone.GetUtcOffset(t));
    }

    private static TimeZoneInfo? Zone(string? id)
    {
        if (string.IsNullOrEmpty(id)) return null;
        try { return TimeZoneInfo.FindSystemTimeZoneById(id); }
        catch (Exception e) when (e is TimeZoneNotFoundException or InvalidTimeZoneException) { }
        if (TimeZoneInfo.TryConvertWindowsIdToIanaId(id, out var iana))
            try { return TimeZoneInfo.FindSystemTimeZoneById(iana); } catch (Exception) { }
        return null;
    }

    [GeneratedRegex(@"^(-)?P(?:(\d+)W)?(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$")]
    private static partial Regex DurationPattern();

    private static TimeSpan? Duration(string value)
    {
        var m = DurationPattern().Match(value.Trim());
        if (!m.Success) return null;
        int N(int g) => m.Groups[g].Success ? int.Parse(m.Groups[g].Value, CultureInfo.InvariantCulture) : 0;
        var span = new TimeSpan(N(2) * 7 + N(3), N(4), N(5), N(6));
        return m.Groups[1].Success ? -span : span;
    }

    private static readonly string[] Days = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"];

    // Occurrences of a repeating event's start between from and to, in the event's own local time.
    private static List<DateTimeOffset> Expand(DateTimeOffset start, string rule, DateTimeOffset from, DateTimeOffset to)
    {
        var p = rule.Split(';').Select(x => x.Split('=', 2)).Where(x => x.Length == 2).ToDictionary(x => x[0].ToUpperInvariant(), x => x[1]);
        var freq = p.GetValueOrDefault("FREQ", "");
        var interval = int.TryParse(p.GetValueOrDefault("INTERVAL"), out var i) && i > 0 ? i : 1;
        var count = int.TryParse(p.GetValueOrDefault("COUNT"), out var c) ? c : int.MaxValue;
        var until = p.TryGetValue("UNTIL", out var u) ? Time(u, null, out _) : null;
        var byDay = p.TryGetValue("BYDAY", out var bd)
            ? bd.Split(',').Select(d => Array.IndexOf(Days, d.Trim()[^2..].ToUpperInvariant())).Where(d => d >= 0).ToHashSet()
            : null;

        var list = new List<DateTimeOffset>();
        var produced = 0;
        var local = start.DateTime;
        var offsetFor = (DateTime t) => start.Offset;
        DateTimeOffset At(DateTime t) => new(t, offsetFor(t));

        for (var step = 0; step < 5000 && produced < count; step++)
        {
            IEnumerable<DateTime> candidates = freq switch
            {
                "DAILY" => [local.AddDays(step * interval)],
                "WEEKLY" when byDay is { Count: > 0 } =>
                    Enumerable.Range(0, 7).Select(d => local.AddDays(step * 7 * interval - (int)local.DayOfWeek + d)).Where(t => byDay.Contains((int)t.DayOfWeek)),
                "WEEKLY" => [local.AddDays(step * 7 * interval)],
                "MONTHLY" => [local.AddMonths(step * interval)],
                "YEARLY" => [local.AddYears(step * interval)],
                _ => step == 0 ? [local] : [],
            };
            var any = false;
            foreach (var t in candidates.OrderBy(t => t))
            {
                any = true;
                if (t < local) continue;
                var at = At(t);
                if (until is { } end && at > end) return list;
                if (at > to || produced >= count) return list;
                produced++;
                if (at >= from) list.Add(at);
            }
            if (!any && freq is not ("DAILY" or "WEEKLY" or "MONTHLY" or "YEARLY")) break;
        }
        return list;
    }

    // The services MeetingBar recognises in an invitation's URL, location or notes, as on the Mac.
    [GeneratedRegex(@"https://(([a-z0-9-]+\.)?zoom(gov)?\.us/(j|my|w)/|meet\.google\.com/|teams\.(microsoft|live)\.com/|([a-z0-9-]+\.)?webex\.com/|whereby\.com/|meet\.jit\.si/|(meet\.goto|global\.gotomeeting)\.com/|chime\.aws/|([a-z0-9-]+\.)?bluejeans\.com/|discord\.(gg|com/channels)/|app\.slack\.com/huddle/|join\.skype\.com/|meeting\.zoho\.(com|eu|in)/|([a-z0-9-]+\.)?larksuite\.com/|app\.gather\.town/|around\.co/|app\.livestorm\.co/|(meetings|v)\.ringcentral\.com/)[^\s<>""]*",
                    RegexOptions.IgnoreCase)]
    private static partial Regex MeetingPattern();

    public static string? MeetingLink(string text)
    {
        var m = MeetingPattern().Match(text);
        return m.Success ? m.Value.TrimEnd('.', ',', ')', '>') : null;
    }
}
