using Beanotch.Core;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Now playing: artwork, the player, progress and controls on the left; synced lyrics on the right.
public sealed class MusicPage(Model model) : PanelPage(model)
{
    private readonly Image art = new() { Stretch = Stretch.UniformToFill };
    private readonly TextBlock source = Text("", 9.5, Theme.Accent, FontWeights.SemiBold);
    private readonly TextBlock title = Text("", 16, weight: FontWeights.Bold, display: true);
    private readonly TextBlock artist = Text("", 11, Theme.Dim);
    private readonly Grid progress = new();
    private readonly TextBlock elapsed = Text("", 8.5, Theme.Faint, mono: true);
    private readonly TextBlock remaining = Text("", 8.5, Theme.Faint, mono: true);
    private readonly FontIcon playGlyph = Icon(Glyphs.Play, 14, Theme.Rgb(1, 1, 1));
    private readonly Slider volume = new() { Minimum = 0, Maximum = 100, StepFrequency = 1 };
    private readonly StackPanel lyrics = V(8);
    private readonly TextBlock credit = Text("LRCLIB", 7.5, Theme.Faint, FontWeights.SemiBold);
    private string shownLine = "\0";
    private bool settingVolume;

    protected override FrameworkElement Build()
    {
        var media = Model.Media;
        var cover = new Border
        {
            Width = S(64),
            Height = S(64),
            CornerRadius = new CornerRadius(S(10)),
            Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.06)),
            Child = art,
        };
        var info = V(2, source, title, artist);
        info.VerticalAlignment = VerticalAlignment.Center;
        var head = Columns(12, (cover, null), (info, 1));

        var times = Columns(0, (elapsed, 1), (remaining, null));
        var play = Plain(new Grid { Width = S(40), Height = S(40), Children = { Center(playGlyph) } }, media.TogglePlay, Theme.Accent, 20);
        var controls = H(10,
            Plain(new Grid { Width = S(30), Height = S(30), Children = { Center(Icon(Glyphs.Previous, 11)) } }, media.Previous, Theme.WithAlpha(Theme.Ink, 0.08), 15),
            play,
            Plain(new Grid { Width = S(30), Height = S(30), Children = { Center(Icon(Glyphs.Next, 11)) } }, media.Next, Theme.WithAlpha(Theme.Ink, 0.08), 15));
        controls.HorizontalAlignment = HorizontalAlignment.Center;

        volume.Resources["SliderTrackValueFill"] = Theme.Brush(Theme.Accent);
        volume.Resources["SliderThumbBackground"] = Theme.Brush(Theme.Ink);
        volume.ValueChanged += (_, e) => { if (!settingVolume) Audio.SetSpeaker(e.NewValue / 100); };
        var volumeRow = Columns(8, (Icon(Glyphs.Volume, 10, Theme.Dim), null), (volume, 1));

        // Compact sits on the panel itself, with no card around it, and keeps to the main controls.
        var compact = Model.Settings.Size == PanelSize.Compact;
        var player = Rows(8, (head, null), (null, 1), (progress, null), (times, null), (controls, null), (compact ? null : volumeRow, null));
        player.Width = S(compact ? 230 : 260);

        var lyricColumn = Rows(0, (lyrics, 1), (compact ? null : credit, null));
        lyrics.VerticalAlignment = VerticalAlignment.Center;
        credit.HorizontalAlignment = HorizontalAlignment.Right;
        var divider = new Border { Width = 1, Background = Theme.Brush(Theme.Stroke) };
        var columns = Columns(compact ? 14 : 18, (player, null), (divider, null), (lyricColumn, 1));
        return compact ? new Border { Child = columns, Padding = new Thickness(S(4)) } : Card(columns, 14, 16);
    }

    public override void Refresh()
    {
        var media = Model.Media;
        art.Source = media.Art;
        source.Text = media.HasTrack ? media.Source : "";
        title.Text = media.HasTrack ? media.Title : "Nothing playing";
        artist.Text = media.HasTrack ? media.Artist : "Play something in Spotify, a browser or Media Player";
        if (Audio.Speaker() is { } v)
        {
            settingVolume = true;
            volume.Value = Math.Round(v.Level * 100);
            settingVolume = false;
        }
        shownLine = "\0";
        Tick();
    }

    public override void Tick()
    {
        var media = Model.Media;
        playGlyph.Glyph = media.Playing ? Glyphs.Pause : Glyphs.Play;
        var duration = media.Duration;
        var position = media.Position;
        var share = duration > TimeSpan.Zero ? position / duration : 0;
        progress.Children.Clear();
        progress.Children.Add(Bar(share, Theme.Accent, 4));
        elapsed.Text = Clock(position);
        remaining.Text = duration > TimeSpan.Zero ? "-" + Clock(duration - position) : "";
        if (title.Text != (media.HasTrack ? media.Title : "Nothing playing")) Refresh();
        Lyrics(media.Lines, media.CurrentLine);
    }

    // Two lines before and after the one being sung, which is larger and in the accent colour.
    private void Lyrics(IReadOnlyList<LyricLine> lines, LyricLine? current)
    {
        var key = current?.Text + "|" + lines.Count;
        if (key == shownLine) return;
        shownLine = key;
        lyrics.Children.Clear();
        if (lines.Count == 0)
        {
            lyrics.Children.Add(Text(Model.Media.HasTrack ? "No synced lyrics for this song" : "Lyrics show up here", 11, Theme.Faint));
            return;
        }
        var index = current is null ? -1 : IndexOf(lines, current);
        for (var i = index - 2; i <= index + 2; i++)
        {
            if (i < 0 || i >= lines.Count) continue;
            var now = i == index;
            var text = Text(lines[i].Text, now ? 15 : 11, now ? Theme.Accent : Math.Abs(i - index) == 1 ? Theme.Dim : Theme.Faint,
                            now ? FontWeights.Bold : FontWeights.Normal, wrap: now);
            lyrics.Children.Add(text);
        }
    }

    private static int IndexOf(IReadOnlyList<LyricLine> lines, LyricLine line)
    {
        for (var i = 0; i < lines.Count; i++) if (ReferenceEquals(lines[i], line)) return i;
        return -1;
    }

    private static string Clock(TimeSpan span) => span.TotalHours >= 1 ? span.ToString(@"h\:mm\:ss") : span.ToString(@"m\:ss");
}
