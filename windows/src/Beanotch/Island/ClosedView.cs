using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using static Beanotch.Ui.Ui;

namespace Beanotch.Island;

// What the closed island shows, most urgent first: a notice (volume, mic in use, Bluetooth, battery, Caps Lock,
// screenshot), a call, a download, a terminal command, the current lyric line or track, the coming prayer, and otherwise just the time.
public sealed class ClosedView
{
    private readonly Model model;
    private readonly FontIcon icon = Icon(Glyphs.Music, 10);
    private readonly TextBlock left = Text("", 10.5, weight: FontWeights.SemiBold);
    private readonly TextBlock right = Text("", 10.5, weight: FontWeights.SemiBold);
    private readonly Border level = new();
    private readonly Grid row;
    private readonly PetView pet;

    public FrameworkElement View { get; }

    public ClosedView(Model model)
    {
        this.model = model;
        left.Foreground = Theme.Brush(Theme.Rgb(1, 1, 1));
        level.Width = S(56);
        pet = new PetView(() => model.Mood);
        row = Columns(8, (pet.View, null), (icon, null), (left, 1), (level, null), (right, null));
        row.Padding = new Thickness(S(13), 0, S(13), 0);
        row.VerticalAlignment = VerticalAlignment.Center;
        View = row;
    }

    // Lays out the content and returns the width the island needs, in Mac points.
    public double Update(Notice? notice)
    {
        var white = Theme.Rgb(1, 1, 1);
        row.Visibility = Visibility.Visible;
        level.Visibility = Visibility.Collapsed;
        pet.Show(false);
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
            return 300;
        }

        if (model.Watchers.CallSince is { } call)
        {
            var muted = Controls.MicMuted;
            Show(model.Watchers.CallCamera ? Glyphs.Camera : Glyphs.Mic, Theme.Red, "In a call" + (muted ? " · muted" : ""), Clock(DateTimeOffset.Now - call));
            return 250;
        }

        if (model.Watchers.Downloading is { } download)
        {
            Show(Glyphs.Download, Theme.Good, download.Name, Format.Rate(download.Rate));
            return 300;
        }

        if (model.Runs.Current is { } run)
        {
            Show("\uE756", Theme.Accent, run.Name, DevRuns.Duration(DateTimeOffset.Now - run.Started));
            return 300;
        }

        var meeting = model.NextEvent;
        if (meeting is not null && model.Settings.MeetingAlerts && meeting.Start - DateTimeOffset.Now is var soon && soon <= TimeSpan.FromMinutes(10))
        {
            Show(Glyphs.Calendar, Theme.Accent2, meeting.Title, soon <= TimeSpan.Zero ? "now" : "in " + Model.Countdown(soon));
            return 300;
        }

        if (model.Focus.Running)
        {
            Show(Glyphs.Clock, model.Focus.OnBreak ? Theme.Good : Theme.Accent, model.Focus.OnBreak ? "Break" : "Focus", Clock(model.Focus.Left));
            level.Child = Bar(model.Focus.Progress, model.Focus.OnBreak ? Theme.Good : Theme.Accent, 4);
            level.Visibility = Visibility.Visible;
            return 250;
        }

        if (model.Timer.Running)
        {
            Show(Glyphs.Clock, Theme.Amber, "Timer", Clock(model.Timer.Left));
            return 210;
        }

        var media = model.Media;
        if (media.Playing && media.HasTrack)
        {
            var line = model.Settings.Lyrics ? media.CurrentLine?.Text : null;
            Show(Glyphs.Music, Theme.Accent, string.IsNullOrEmpty(line) ? media.Title : line, "");
            left.Foreground = Theme.Brush(string.IsNullOrEmpty(line) ? white : Theme.Accent);
            return 340;
        }

        var next = model.NextPrayer;
        var until = next.Time - DateTimeOffset.Now;
        if (model.Settings.PrayerCountdown && model.Visible(Tab.Prayer) && until < TimeSpan.FromHours(1))
        {
            Show(Glyphs.Moon, Theme.Accent2, model.Label(next), "in " + Model.Countdown(until));
            return 230;
        }

        // Idle: the pet, when it's switched on.
        if (model.Settings.NotchPet)
        {
            pet.Show(true);
            icon.Visibility = Visibility.Collapsed;
            var mood = model.Mood;
            Show(Glyphs.Music, Theme.Accent, "", mood switch
            {
                Model.PetMood.Sleepy => "zzz", Model.PetMood.Panic => "hot!", Model.PetMood.Eating => "nom", Model.PetMood.Dancing => "♪", _ => "",
            });
            return 230;
        }

        // Idle: an empty black notch, as on a MacBook, unless the time was asked for.
        if (!model.Settings.IdleClock)
        {
            row.Visibility = Visibility.Collapsed;
            return 180;
        }
        Show(Glyphs.Clock, Theme.Rgb(1, 1, 1, 0.55), DateTime.Now.ToString("ddd d MMM"), DateTime.Now.ToString("HH.mm"));
        right.Foreground = Theme.Brush(white);
        return 190;
    }

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
