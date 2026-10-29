using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.System.Power;
using static Beanotch.Ui.Ui;

namespace Beanotch.Island;

// What the closed island shows, most urgent first: a notice (volume, mic in use, Bluetooth, battery, Caps Lock,
// screenshot), a call, a download, a terminal command, the music, the coming prayer, and otherwise what was picked for
// idle: the pet, the time, the date, the weather or the battery, or nothing at all. As small as the words allow.
public sealed class ClosedView
{
    private readonly Model model;
    private readonly FontIcon icon = Icon(Glyphs.Music, 10);
    private readonly TextBlock left = Text("", 10.5, weight: FontWeights.SemiBold);
    private readonly TextBlock right = Text("", 10.5, weight: FontWeights.SemiBold);
    private readonly Border level = new();
    private readonly Grid row;
    private readonly PetView pet;
    // The music's beat: four bars that bob while it plays.
    private readonly StackPanel beat = H(2);
    private double width;
    private bool petShows;

    public FrameworkElement View { get; }
    // The pet, for the window to hand clicks, rests, scrolls and shakes to.
    public FrameworkElement PetSpot => pet.View;
    public bool PetShowing => petShows;

    public ClosedView(Model model, Func<(Windows.Foundation.Point At, double Scale)?> petAnchor)
    {
        this.model = model;
        left.Foreground = Theme.Brush(Theme.Rgb(1, 1, 1));
        level.Width = S(56);
        pet = new PetView(() => model.Mood, () => model.Settings.PetKind, petAnchor, accessory: () => model.Settings.PetAccessory,
                          praying: () => model.Pet.Praying, walkTo: () => model.Pet.Walk, walkDistance: () => S(width - 70));
        pet.Shaken += model.Pet.Shake;
        for (var i = 0; i < 4; i++)
            beat.Children.Add(new Border { Width = S(2.5), Height = S(6), CornerRadius = new CornerRadius(S(1.25)), VerticalAlignment = VerticalAlignment.Center });
        row = Columns(8, (pet.View, null), (icon, null), (left, 1), (level, null), (right, null), (beat, null));
        row.Padding = new Thickness(S(13), 0, S(13), 0);
        row.VerticalAlignment = VerticalAlignment.Center;
        View = row;
    }

    // The pet keeps the left corner while the island is idle or only playing music (in place of the cover); anything
    // with words takes the room for a moment, as the pet steps aside.
    public double Update(Notice? notice)
    {
        petShows = false;
        beat.Visibility = Visibility.Collapsed;
        width = Content(notice);
        pet.Show(petShows);
        if (!petShows) return width;
        row.Visibility = Visibility.Visible;
        return width + 44;
    }

    // Room for a notice's words, between a short one and a long one.
    private static double Fit(string left, string right, bool bar) => Math.Clamp(96 + (left.Length + right.Length) * 6.6 + (bar ? 64 : 0), 190, 330);

    // Lays out the content and returns the width the island needs, in Mac points.
    private double Content(Notice? notice)
    {
        var white = Theme.Rgb(1, 1, 1);
        row.Visibility = Visibility.Visible;
        level.Visibility = Visibility.Collapsed;
        icon.Visibility = Visibility.Visible;
        right.Foreground = Theme.Brush(Theme.Rgb(1, 1, 1, 0.7));

        if (notice is not null)
        {
            Show(notice.Glyph, notice.Color, notice.Left, notice.Right);
            if (notice.Level is double value)
            {
                level.Child = Bar(value, notice.Color, 4);
                level.Visibility = Visibility.Visible;
            }
            return Fit(notice.Left, notice.Right, notice.Level is not null);
        }

        if (model.Watchers.CallSince is { } call)
        {
            var muted = Controls.MicMuted;
            Show(model.Watchers.CallCamera ? Glyphs.Camera : Glyphs.Mic, Theme.Red, "In a call" + (muted ? " · muted" : ""), Clock(DateTimeOffset.Now - call));
            return 220;
        }

        if (model.Watchers.Downloading is { } download)
        {
            Show(Glyphs.Download, Theme.Good, download.Name, Format.Rate(download.Rate));
            return 260;
        }

        if (model.Runs.Current is { } run)
        {
            Show("\uE756", Theme.Accent, run.Name, DevRuns.Duration(DateTimeOffset.Now - run.Started));
            return 260;
        }

        var meeting = model.NextEvent;
        if (meeting is not null && model.Settings.MeetingAlerts && meeting.Start - DateTimeOffset.Now is var soon && soon <= TimeSpan.FromMinutes(10))
        {
            Show(Glyphs.Calendar, Theme.Accent2, meeting.Title, soon <= TimeSpan.Zero ? "now" : "in " + Model.Countdown(soon));
            return 260;
        }

        if (model.Focus.Running)
        {
            Show(Glyphs.Clock, model.Focus.OnBreak ? Theme.Good : Theme.Accent, model.Focus.OnBreak ? "Break" : "Focus", Clock(model.Focus.Left));
            level.Child = Bar(model.Focus.Progress, model.Focus.OnBreak ? Theme.Good : Theme.Accent, 4);
            level.Visibility = Visibility.Visible;
            return 220;
        }

        if (model.Timer.Running)
        {
            Show(Glyphs.Clock, Theme.Amber, "Timer", Clock(model.Timer.Left));
            return 180;
        }

        var media = model.Media;
        if (media.Playing && media.HasTrack && model.Settings.MusicShows == MusicShows.Lyrics)
        {
            var line = media.CurrentLine?.Text;
            Show(Glyphs.Music, Theme.Accent, string.IsNullOrEmpty(line) ? media.Title : line, "");
            left.Foreground = Theme.Brush(string.IsNullOrEmpty(line) ? white : Theme.Accent);
            return 340;
        }
        // Cover & beat: a note (or the pet, dancing) and the bars, and no words, so the island stays small.
        if (media.Playing && media.HasTrack && model.Settings.MusicShows == MusicShows.Beat)
        {
            Show(Glyphs.Music, Theme.Accent, "", "");
            petShows = model.Settings.NotchPet;
            if (petShows) icon.Visibility = Visibility.Collapsed;
            Beat();
            return 120;
        }

        var next = model.NextPrayer;
        var until = next.Time - DateTimeOffset.Now;
        if (model.Settings.PrayerCountdown && model.Visible(Tab.Prayer) && until < TimeSpan.FromHours(1))
        {
            Show(Glyphs.Moon, Theme.Accent2, model.Label(next), "in " + Model.Countdown(until));
            return 200;
        }

        // Idle: what was picked for each side, the pet in its corner on the left with its word beside it.
        var settings = model.Settings;
        petShows = settings.NotchPet;
        var (leftGlyph, leftText) = petShows ? (null, PetLine()) : Item(settings.IdleLeft);
        var (_, rightText) = Item(settings.IdleRight);
        if (!petShows && leftText.Length == 0 && rightText.Length == 0)
        {
            // An empty black notch, as on a MacBook.
            row.Visibility = Visibility.Collapsed;
            return 150;
        }
        Show(leftGlyph ?? Glyphs.Clock, Theme.Rgb(1, 1, 1, 0.55), leftText, rightText);
        icon.Visibility = leftGlyph is null ? Visibility.Collapsed : Visibility.Visible;
        left.Foreground = Theme.Brush(Theme.Rgb(1, 1, 1, petShows ? 0.6 : 0.8));
        right.Foreground = Theme.Brush(white);
        return Math.Clamp(110 + (leftText.Length + rightText.Length) * 6.6 + (leftGlyph is null ? 0 : 18), 150, 260);
    }

    // Auto, made concrete: a meeting or a prayer within half an hour, the battery when it's low or charging, and
    // otherwise the time.
    private IdleItem Resolve(IdleItem item)
    {
        if (item != IdleItem.Auto) return item;
        var now = DateTimeOffset.Now;
        if (model.NextEvent is { } e && e.Start - now < TimeSpan.FromMinutes(30)) return IdleItem.Event;
        if (model.Visible(Tab.Prayer) && model.NextPrayer.Time - now < TimeSpan.FromMinutes(30)) return IdleItem.Prayer;
        if (PowerManager.BatteryStatus != BatteryStatus.NotPresent
            && (PowerManager.PowerSupplyStatus != PowerSupplyStatus.NotPresent || PowerManager.RemainingChargePercent < 20)) return IdleItem.Battery;
        return IdleItem.Time;
    }

    // One idle side: its icon (shown on the left) and its words.
    private (string? Glyph, string Text) Item(IdleItem item)
    {
        switch (Resolve(item))
        {
            case IdleItem.Event when model.NextEvent is { } e:
                return (Glyphs.Calendar, $"{(e.Title.Length > 14 ? e.Title[..14] + "…" : e.Title)} {Model.Clock(e.Start)}");
            case IdleItem.Prayer when model.Visible(Tab.Prayer):
                return (Glyphs.Moon, $"{model.Label(model.NextPrayer)} {Model.Clock(model.NextPrayer.Time)}");
            case IdleItem.Time: return (Glyphs.Clock, DateTime.Now.ToString("HH.mm"));
            case IdleItem.Date: return (Glyphs.Calendar, DateTime.Now.ToString("ddd d"));
            case IdleItem.Weather when model.Weather is { } w: return (Glyphs.Sun, $"{Math.Round(w.Temp)}°");
            case IdleItem.Battery when PowerManager.BatteryStatus != BatteryStatus.NotPresent:
                return (PowerManager.PowerSupplyStatus != PowerSupplyStatus.NotPresent ? Glyphs.Charging : Glyphs.Battery, $"{PowerManager.RemainingChargePercent}%");
            default: return (null, "");
        }
    }

    // The bars bob at their own pace, a fresh height each tick.
    private void Beat()
    {
        beat.Visibility = Visibility.Visible;
        var t = Environment.TickCount64 / 400;
        for (var i = 0; i < beat.Children.Count; i++)
        {
            var bar = (Border)beat.Children[i];
            bar.Height = S(4 + (t * 7 + i * 13) % 9);
            bar.Background = Theme.Brush(Theme.Accent);
        }
    }

    private string PetLine() => model.Mood switch
    {
        Model.PetMood.Sleepy => "zzz", Model.PetMood.Panic => "hot!", Model.PetMood.Eating => "nom", Model.PetMood.Dancing => "♪",
        Model.PetMood.Surprised => "!", Model.PetMood.Late => "bed?", Model.PetMood.Thirsty => "water?",
        Model.PetMood.Love => "♥", Model.PetMood.Dizzy => "@_@", Model.PetMood.Sad => "aw…", Model.PetMood.Party => "yay!",
        Model.PetMood.Focus => "focus", Model.PetMood.Coffee => "break", Model.PetMood.Tired => "low…", Model.PetMood.Charged => "zap!",
        Model.PetMood.Hungry => $"{model.Pet.Name} is hungry · click", Model.PetMood.Spin => "wheee", Model.PetMood.Wave => "hi!",
        Model.PetMood.Groove => "♪ new song", _ => "",
    };

    private static string Clock(TimeSpan t) => t.TotalHours >= 1 ? t.ToString(@"h\:mm\:ss") : t.ToString(@"mm\:ss");

    private void Show(string glyph, Windows.UI.Color color, string text, string trailing)
    {
        icon.Glyph = glyph;
        icon.Foreground = Theme.Brush(color);
        left.Text = text;
        left.Foreground = Theme.Brush(Theme.Rgb(1, 1, 1));
        right.Text = trailing;
        right.Visibility = trailing.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
    }
}
