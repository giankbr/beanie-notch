using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Bar: one slim row and no menu, as on the Mac. The song and its controls, the focus timer, and what's coming up.
public sealed class BarPage(Model model) : PanelPage(model)
{
    private readonly Image art = new() { Stretch = Stretch.UniformToFill };
    private readonly TextBlock song = Text("", 11.5, weight: FontWeights.Bold);
    private readonly TextBlock artist = Text("", 9.5, Theme.Dim);
    private readonly FontIcon playGlyph = Icon(Glyphs.Play, 10, Theme.Rgb(1, 1, 1));
    private readonly FontIcon focusGlyph = Icon(Glyphs.Clock, 10);
    private readonly TextBlock focusTime = Text("", 13, weight: FontWeights.Bold);
    private readonly TextBlock focusPhase = Text("", 9, Theme.Dim);
    private readonly FontIcon nextGlyph = Icon(Glyphs.Calendar, 11, Theme.Accent2);
    private readonly TextBlock nextTitle = Text("", 10.5, weight: FontWeights.SemiBold);
    private readonly TextBlock nextTime = Text("", 9, Theme.Dim);

    protected override FrameworkElement Build()
    {
        var media = Model.Media;
        var cover = new Border { Width = S(36), Height = S(36), CornerRadius = new CornerRadius(S(8)), Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.06)), Child = art };
        var info = V(1, song, artist);
        info.VerticalAlignment = VerticalAlignment.Center;
        var play = Plain(new Grid { Width = S(28), Height = S(28), Children = { Center(playGlyph) } }, media.TogglePlay, Theme.Accent, 14);
        var skip = Plain(new Grid { Width = S(22), Height = S(22), Children = { Center(Icon(Glyphs.Next, 8.5)) } }, media.Next, Theme.WithAlpha(Theme.Ink, 0.08), 11);
        var controls = H(5, play, skip);
        controls.VerticalAlignment = VerticalAlignment.Center;

        var focusButton = Plain(new Grid { Width = S(28), Height = S(28), Children = { Center(focusGlyph) } }, () => { Model.Focus.Toggle(); Tick(); },
                                Theme.WithAlpha(Theme.Ink, 0.08), 14);
        var focusText = V(0, focusTime, focusPhase);
        focusText.VerticalAlignment = VerticalAlignment.Center;

        var nextText = V(0, nextTitle, nextTime);
        nextText.VerticalAlignment = VerticalAlignment.Center;
        nextText.MaxWidth = S(120);

        Border Divider() => new() { Width = 1, Height = S(30), Background = Theme.Brush(Theme.Stroke), VerticalAlignment = VerticalAlignment.Center };
        var gear = IconButton(Glyphs.Settings, () => Model.OpenSettings(Tab.Settings), 9, Theme.Faint, "Settings and tools", 20);
        var row = Columns(12, (cover, null), (info, 1), (controls, null), (Divider(), null), (focusButton, null), (focusText, null),
                          (Divider(), null), (nextGlyph, null), (nextText, null), (gear, null));
        row.VerticalAlignment = VerticalAlignment.Center;
        return row;
    }

    public override void Refresh()
    {
        var media = Model.Media;
        art.Source = media.Art;
        song.Text = media.HasTrack ? media.Title : "Nothing playing";
        artist.Text = media.HasTrack ? media.Artist : "Play something in any app";
        Tick();
    }

    public override void Tick()
    {
        var media = Model.Media;
        if (song.Text != (media.HasTrack ? media.Title : "Nothing playing")) { Refresh(); return; }
        playGlyph.Glyph = media.Playing ? Glyphs.Pause : Glyphs.Play;
        var timer = Model.Focus;
        focusGlyph.Glyph = timer.Running ? Glyphs.Pause : Glyphs.Clock;
        focusTime.Text = timer.Left.ToString(timer.Left.TotalHours >= 1 ? @"h\:mm\:ss" : @"mm\:ss");
        focusPhase.Text = timer.OnBreak ? "Break" : "Focus";

        // Whichever comes first: the next event or the next prayer; with neither, the day.
        var e = Model.NextEvent;
        var p = Model.Visible(Tab.Prayer) ? Model.NextPrayer : null;
        if (e is not null && (p is null || e.Start <= p.Time))
            (nextGlyph.Glyph, nextTitle.Text, nextTime.Text) = (Glyphs.Calendar, e.Title, Model.Clock(e.Start));
        else if (p is not null)
            (nextGlyph.Glyph, nextTitle.Text, nextTime.Text) = (Glyphs.Moon, Model.Label(p), Model.Clock(p.Time));
        else
            (nextGlyph.Glyph, nextTitle.Text, nextTime.Text) = (Glyphs.Sun, DateTime.Now.ToString("dddd"), DateTime.Now.ToString("d MMM"));
    }
}
