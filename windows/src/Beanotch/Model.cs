using System.Globalization;
using Beanotch.Core;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Dispatching;

namespace Beanotch;

public enum Tab { Home, Today, Prayer, Music, Shelf, Clipboard, Ai, Controls, Tools, Settings }

// Everything the island shows, in one place, like AppModel on the Mac.
public sealed class Model
{
    public AppSettings Settings { get; } = AppSettings.Load();
    public SystemStats Stats { get; } = new();
    public Cleaner Cleaner { get; } = new();
    public MediaWatcher Media { get; }
    public ClipboardWatcher Clipboard { get; }
    public Shelf Shelf { get; }
    public Watchers Watchers { get; }
    public FocusTimer Focus { get; } = new();
    public CountdownTimer Timer { get; } = new();
    public Updater Updater { get; } = new();
    public DevRuns Runs { get; }
    public Rates Rates { get; }
    public Quakes Quakes { get; }
    public SmartCopy SmartCopy { get; }
    public Ambient Ambient { get; } = new();
    private DateTimeOffset fedUntil, surprisedUntil;

    // The pet jumps at each alert.
    public void Surprise() => surprisedUntil = DateTimeOffset.Now.AddSeconds(2.5);
    public WeatherReport? Weather { get; private set; }
    public IReadOnlyList<CalendarEvent> Events { get; private set; } = [];
    public bool CalendarFailed { get; private set; }

    private static readonly HttpClient Http = new() { Timeout = TimeSpan.FromSeconds(15) };
    private DateTime weatherAt, calendarAt;
    private readonly HashSet<string> announced = [];

    // Reminders for the closed island: meetings, tasks, prayers, timers.
    public event Action<Notice>? Notice;

    public Tab Tab { get; set; } = Tab.Home;
    public bool Expanded { get; set; }

    public Model(DispatcherQueue ui)
    {
        Media = new MediaWatcher(ui);
        Clipboard = new ClipboardWatcher(Settings);
        Shelf = new Shelf(Settings);
        Watchers = new Watchers(Settings, ui);
        Watchers.Screenshot += path => Shelf.Add([path]);
        Focus.Choose(FocusPreset.All[Math.Clamp(Settings.FocusPreset, 0, FocusPreset.All.Length - 1)]);
        Focus.Finished += text => Raise(Glyphs.Clock, Ui.Theme.Accent, text, Focus.OnBreak ? $"{Focus.Preset.Work} min" : $"{Focus.Preset.Rest} min", 5);
        Timer.Finished += () => Raise(Glyphs.Clock, Ui.Theme.Amber, "Timer done", Timer.Length.TotalMinutes + " min", 6);
        Runs = new DevRuns(ui);
        Runs.Notice += n => Notice?.Invoke(n);
        Runs.Start();
        Rates = new Rates(Settings);
        Quakes = new Quakes(Settings);
        Quakes.Notice += n => Notice?.Invoke(n);
        SmartCopy = new SmartCopy(Settings, Rates) { Copy = Clipboard.CopyText };
        SmartCopy.Notice += n => Notice?.Invoke(n);
        Clipboard.Copied += SmartCopy.Check;
        Shelf.Items.CollectionChanged += (_, e) => { if (e.NewItems is { Count: > 0 }) fedUntil = DateTimeOffset.Now.AddSeconds(4); };
    }

    private void Raise(string glyph, Windows.UI.Color color, string left, string right, double seconds) =>
        Notice?.Invoke(new Notice(glyph, color, left, right, TimeSpan.FromSeconds(seconds), Essential: true));

    public enum PetMood { Happy, Sleepy, Panic, Eating, Dancing, Surprised, Late }

    // How the island's pet is feeling, as on the Mac (Windows has no drink reminder, so it's never thirsty).
    public PetMood Mood =>
        DateTimeOffset.Now < surprisedUntil ? PetMood.Surprised
        : DateTimeOffset.Now < fedUntil ? PetMood.Eating
        : Stats.Cpu > 0.85 ? PetMood.Panic
        : Services.Native.Idle > TimeSpan.FromMinutes(3) ? PetMood.Sleepy
        : Media.Playing ? PetMood.Dancing
        : DateTime.Now.Hour < 4 ? PetMood.Late
        : PetMood.Happy;

    public bool Ramadan => new UmAlQuraCalendar().GetMonth(DateTime.Now) == 9;

    // In Ramadan Maghrib is when the fast breaks.
    public string Label(PrayerEntry e) => Ramadan && e.Name == "Maghrib" ? "Iftar" : e.Name;

    // In Ramadan: how the fast stands, for the Prayer page.
    public string? Fasting(DateTimeOffset now)
    {
        if (!Ramadan) return null;
        var today = PrayersToday;
        if (today.FirstOrDefault(e => e.Name == "Imsak") is not { } imsak || today.FirstOrDefault(e => e.Name == "Maghrib") is not { } maghrib) return null;
        if (now < imsak.Time) return $"Sahur · Imsak in {Countdown(imsak.Time - now)}";
        if (now < maghrib.Time) return $"Fasting · {Countdown(maghrib.Time - now)} to iftar at {Clock(maghrib.Time)}";
        var tomorrow = PrayerTimes.Compute(DateOnly.FromDateTime(DateTime.Now.AddDays(1)), Settings.Place, Settings.Method).FirstOrDefault(e => e.Name == "Imsak");
        return tomorrow is null ? null : $"Fast broken · Imsak tomorrow at {Clock(tomorrow.Time)}";
    }

    public bool Visible(Tab tab) => tab is Tab.Home or Tab.Settings || !Settings.HiddenTabs.Contains(tab.ToString());

    // Weather every half hour, the calendar every ten minutes; both only while there's something to show them for.
    public async Task RefreshDataAsync(bool force = false)
    {
        if (force || DateTime.UtcNow - weatherAt > TimeSpan.FromMinutes(30))
        {
            weatherAt = DateTime.UtcNow;
            Weather = await Core.Weather.FetchAsync(Http, Settings.Place.Lat, Settings.Place.Lng) ?? Weather;
        }
        if (Settings.CalendarUrl.Length > 0 && (force || DateTime.UtcNow - calendarAt > TimeSpan.FromMinutes(10)))
        {
            calendarAt = DateTime.UtcNow;
            var now = DateTimeOffset.Now;
            var events = await Core.Calendar.FetchAsync(Http, Settings.CalendarUrl, now.AddHours(-12), now.AddDays(32));
            CalendarFailed = events.Count == 0 && Events.Count == 0;
            if (events.Count > 0) Events = events;
        }
        else if (Settings.CalendarUrl.Length == 0) Events = [];
    }

    public CalendarEvent? NextEvent =>
        Events.Where(e => !e.AllDay && e.End > DateTimeOffset.Now).OrderBy(e => e.Start).FirstOrDefault();

    // Called a few times a second: timers, and reminders that come due.
    public void Tick()
    {
        Focus.Tick();
        Timer.Tick();
        var now = DateTimeOffset.Now;
        if (Settings.MeetingAlerts && NextEvent is { } meeting && meeting.Start - now is var until && until <= TimeSpan.FromMinutes(5) && until > TimeSpan.Zero
            && announced.Add("meeting|" + meeting.Title + meeting.Start))
            Raise(Glyphs.Calendar, Ui.Theme.Accent2, meeting.Title, "in " + Countdown(until), 8);
        if (Settings.PrayerReminder > 0 && NextPrayer is var prayer && prayer.Time - now is var left
            && left <= TimeSpan.FromMinutes(Settings.PrayerReminder) && left > TimeSpan.Zero && announced.Add("prayer|" + prayer.Time))
            Raise(Glyphs.Moon, Ui.Theme.Accent2, Label(prayer), "in " + Countdown(left), 8);
        if (Ramadan && Settings.PrayerCountdown)
            foreach (var e in PrayersToday.Where(e => e.Name is "Imsak" or "Maghrib"))
            {
                var gap = e.Time - now;
                if (e.Name == "Imsak" && gap <= TimeSpan.FromMinutes(15) && gap > TimeSpan.Zero && announced.Add("sahur|" + e.Time))
                    Raise("\uE7EC", Ui.Theme.Amber, "Imsak in " + Countdown(gap), "Finish sahur · " + Clock(e.Time), 10);
                if (gap <= TimeSpan.Zero && gap > TimeSpan.FromMinutes(-1) && announced.Add("fast|" + e.Time))
                    Raise(Glyphs.Moon, Ui.Theme.Accent, e.Name == "Imsak" ? "Imsak · the fast begins" : "Iftar · break the fast", Clock(e.Time), e.Name == "Imsak" ? 12 : 20);
            }
        // The focus sound plays through focus stretches only: not on breaks, and not while paused.
        if (Focus.Running && !Focus.OnBreak && Enum.TryParse<AmbientSound>(Settings.FocusSound, out var sound)) Ambient.Play(sound);
        else if (Ambient.Playing is not null) Ambient.Stop();
        foreach (var task in Settings.Tasks.Where(t => !t.Done && !t.Reminded && t.Remind is { } at && at <= now))
        {
            task.Reminded = true;
            Settings.Save();
            Raise(Glyphs.Done, Ui.Theme.Amber, task.Title, "now", 8);
        }
    }

    public static string Title(Tab tab) => tab switch
    {
        Tab.Home => "Overview",
        Tab.Today => "Today",
        Tab.Controls => "Controls",
        Tab.Tools => "Tools",
        Tab.Settings => "Settings",
        Tab.Prayer => "Prayer Times",
        Tab.Music => "Now Playing",
        Tab.Shelf => "Shelf",
        Tab.Clipboard => "Clipboard",
        _ => "AI",
    };

    public IReadOnlyList<PrayerEntry> PrayersToday =>
        PrayerTimes.Compute(DateOnly.FromDateTime(DateTime.Now), Settings.Place, Settings.Method);

    public PrayerEntry NextPrayer =>
        PrayerTimes.Next(DateTimeOffset.Now, DateOnly.FromDateTime(DateTime.Now), Settings.Place, Settings.Method);

    // The Hijri date: in Indonesia with the months as Indonesians write them ("16 Jumadilawal 1448 H"), elsewhere with
    // their common English spellings, as on the Mac.
    public string Hijri
    {
        get
        {
            var cal = new UmAlQuraCalendar();
            var now = DateTime.Now;
            var month = cal.GetMonth(now) - 1;
            var place = Settings.Place;
            if (place.Lat is >= -11.5 and <= 6.5 && place.Lng is >= 94.5 and <= 141.5)
            {
                string[] id = ["Muharam", "Safar", "Rabiulawal", "Rabiulakhir", "Jumadilawal", "Jumadilakhir",
                               "Rajab", "Syakban", "Ramadan", "Syawal", "Zulkaidah", "Zulhijah"];
                return $"{cal.GetDayOfMonth(now)} {id[month]} {cal.GetYear(now)} H";
            }
            string[] en = ["Muharram", "Safar", "Rabi al-Awwal", "Rabi al-Thani", "Jumada al-Ula", "Jumada al-Akhirah",
                           "Rajab", "Shaban", "Ramadan", "Shawwal", "Dhu al-Qadah", "Dhu al-Hijjah"];
            return $"{cal.GetDayOfMonth(now)} {en[month]} {cal.GetYear(now)} AH";
        }
    }

    public static string Clock(DateTimeOffset t) => t.ToLocalTime().ToString("HH.mm", CultureInfo.InvariantCulture);

    public static string Countdown(TimeSpan span) =>
        span.TotalMinutes < 60 ? $"{Math.Max(1, (int)Math.Ceiling(span.TotalMinutes))}m" : $"{(int)span.TotalHours}h {span.Minutes}m";

    // A rough 0–100, as on the Mac: a nearly full disk, memory pressure and piled-up junk each cost points.
    public int Health
    {
        get
        {
            var s = 100.0;
            s -= Math.Max(0, Stats.Disk - 0.75) * 160;
            s -= Math.Max(0, Stats.Ram - 0.8) * 100;
            s -= Math.Min(25, Cleaner.Total / 1_000_000_000.0 * 5);
            return (int)Math.Round(Math.Clamp(s, 0, 100));
        }
    }
}
