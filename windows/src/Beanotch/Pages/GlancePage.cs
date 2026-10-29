using Beanotch.Core;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Glance: one page and no menu, as on the Mac. A card each for what's playing, what's coming up (events and the next
// prayer, or the weather) and the focus timer, read at a look.
public sealed class GlancePage(Model model) : PanelPage(model)
{
    private readonly Image art = new() { Stretch = Stretch.UniformToFill };
    private readonly TextBlock song = Text("", 12, weight: FontWeights.Bold);
    private readonly TextBlock artist = Text("", 10, Theme.Dim);
    private readonly Grid progress = new();
    private readonly FontIcon playGlyph = Icon(Glyphs.Play, 11, Theme.Rgb(1, 1, 1));
    private readonly StackPanel next = V(7);
    private readonly TextBlock focusTime = Text("", 17, weight: FontWeights.Bold);
    private readonly TextBlock focusPhase = Text("", 9, Theme.Dim);
    private readonly Grid focusBar = new();
    private readonly FontIcon focusGlyph = Icon(Glyphs.Play, 12);
    private string shownNext = "";

    protected override FrameworkElement Build()
    {
        var media = Model.Media;
        var cover = new Border { Width = S(44), Height = S(44), CornerRadius = new CornerRadius(S(9)), Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.06)), Child = art };
        var info = V(1, song, artist);
        info.VerticalAlignment = VerticalAlignment.Center;
        Button Round(string glyph, Action act) =>
            Plain(new Grid { Width = S(24), Height = S(24), Children = { Center(Icon(glyph, 9)) } }, act, Theme.WithAlpha(Theme.Ink, 0.08), 12);
        var controls = H(8, Round(Glyphs.Previous, media.Previous),
                         Plain(new Grid { Width = S(30), Height = S(30), Children = { Center(playGlyph) } }, media.TogglePlay, Theme.Accent, 15),
                         Round(Glyphs.Next, media.Next));
        controls.HorizontalAlignment = HorizontalAlignment.Center;
        var now = Card(Rows(8, (Columns(9, (cover, null), (info, 1)), null), (null, 1), (progress, null), (controls, null)), 10, 12);

        var upNext = Card(next, 10, 12);

        var play = Plain(new Grid { Width = S(34), Height = S(34), Children = { Center(focusGlyph) } }, () => { Model.Focus.Toggle(); Tick(); },
                         Theme.WithAlpha(Theme.Ink, 0.08), 17);
        play.HorizontalAlignment = HorizontalAlignment.Center;
        focusTime.HorizontalAlignment = HorizontalAlignment.Center;
        focusPhase.HorizontalAlignment = HorizontalAlignment.Center;
        var focus = Card(Rows(6, (null, 1), (play, null), (focusTime, null), (focusPhase, null), (focusBar, null), (null, 1)), 10, 12);
        focus.Width = S(132);

        return Columns(10, (now, 1), (upNext, 1), (focus, null));
    }

    public override void Refresh()
    {
        var media = Model.Media;
        art.Source = media.Art;
        song.Text = media.HasTrack ? media.Title : "Nothing playing";
        artist.Text = media.HasTrack ? media.Artist : "Play something in any app";
        shownNext = "";
        Tick();
    }

    public override void Tick()
    {
        var media = Model.Media;
        if (song.Text != (media.HasTrack ? media.Title : "Nothing playing")) { Refresh(); return; }
        playGlyph.Glyph = media.Playing ? Glyphs.Pause : Glyphs.Play;
        progress.Children.Clear();
        progress.Children.Add(Bar(media.Duration > TimeSpan.Zero ? media.Position / media.Duration : 0, Theme.Accent, 3));

        var timer = Model.Focus;
        focusGlyph.Glyph = timer.Running ? Glyphs.Pause : Glyphs.Play;
        focusTime.Text = timer.Left.ToString(timer.Left.TotalHours >= 1 ? @"h\:mm\:ss" : @"mm\:ss");
        focusPhase.Text = timer.OnBreak ? "Break" : "Focus";
        focusBar.Children.Clear();
        focusBar.Children.Add(Bar(timer.Progress, timer.OnBreak ? Theme.Good : Theme.Accent, 3));
        Next();
    }

    // Events still to come and the next prayer, in time order, three at most; with none, the weather.
    private void Next()
    {
        var now = DateTimeOffset.Now;
        var rows = Model.Events.Where(e => !e.AllDay && e.End > now).Take(3)
            .Select(e => (e.Start, Glyphs.Calendar, e.Title)).ToList();
        if (Model.Visible(Tab.Prayer) && Model.NextPrayer is { } prayer)
            rows.Add((prayer.Time, Glyphs.Moon, Model.Label(prayer)));
        var shown = rows.OrderBy(r => r.Item1).Take(3).ToList();
        var key = string.Join("|", shown.Select(r => r.Item1.ToString("HHmm") + r.Item3)) + "|" + Model.Weather?.Temp;
        if (key == shownNext) return;
        shownNext = key;
        next.Children.Clear();
        next.Children.Add(Columns(6, (Text("Up next", 11, weight: FontWeights.Bold), 1), (Text(DateTime.Now.ToString("ddd d MMM"), 9, Theme.Faint), null)));
        if (shown.Count == 0)
        {
            if (Model.Weather is { } w)
                next.Children.Add(V(1, Text($"{Math.Round(w.Temp)}°", 16, weight: FontWeights.Bold), Text(Core.Weather.Describe(w.Code), 9, Theme.Dim)));
            next.Children.Add(Text("Nothing on the calendar", 9.5, Theme.Faint));
            return;
        }
        foreach (var (time, glyph, title) in shown)
            next.Children.Add(Columns(7, (Icon(glyph, 9, glyph == Glyphs.Moon ? Theme.Accent2 : Theme.Accent), null),
                                      (Text(Model.Clock(time), 9.5, Theme.Dim, mono: true), null), (Text(title, 10.5, weight: FontWeights.Medium), 1)));
    }
}
