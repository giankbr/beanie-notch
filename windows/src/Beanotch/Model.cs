using System.Globalization;
using Beanotch.Core;
using Beanotch.Services;
using Microsoft.UI.Dispatching;

namespace Beanotch;

public enum Tab { Home, Prayer, Music, Shelf, Clipboard, Ai }

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

    public Tab Tab { get; set; } = Tab.Home;
    public bool Expanded { get; set; }

    public Model(DispatcherQueue ui)
    {
        Media = new MediaWatcher(ui);
        Clipboard = new ClipboardWatcher(Settings);
        Shelf = new Shelf(Settings);
        Watchers = new Watchers(Settings, ui);
        Watchers.Screenshot += path => Shelf.Add([path]);
    }

    public static string Title(Tab tab) => tab switch
    {
        Tab.Home => "Overview",
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

    // The Hijri date in Indonesian month names, from .NET's Umm al-Qura calendar.
    public static string Hijri
    {
        get
        {
            var cal = new UmAlQuraCalendar();
            var now = DateTime.Now;
            string[] months = ["Muharram", "Safar", "Rabiulawal", "Rabiulakhir", "Jumadilawal", "Jumadilakhir",
                               "Rajab", "Syakban", "Ramadan", "Syawal", "Zulkaidah", "Zulhijah"];
            return $"{cal.GetDayOfMonth(now)} {months[cal.GetMonth(now) - 1]} {cal.GetYear(now)} H";
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
