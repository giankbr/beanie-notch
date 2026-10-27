using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Overview: health, CPU, memory, network and disk across the top, then cleanup and quick settings.
public sealed class HomePage(Model model) : PanelPage(model)
{
    private readonly Grid strip = new();
    private readonly StackPanel cleanup = V(4);
    private readonly StackPanel quick = V(4);

    protected override FrameworkElement Build()
    {
        var stripCard = Card(strip, 0, 12);
        var cleanupCard = Card(cleanup, 12, 12);
        var quickCard = Card(quick, 12, 12);
        quickCard.Width = S(220);
        var bottom = Columns(10, (cleanupCard, 1), (quickCard, null));
        return Scroll(V(10, stripCard, bottom));
    }

    public override void Refresh()
    {
        Strip();
        Cleanup();
        Quick();
    }

    private void Strip()
    {
        var s = Model.Stats;
        var score = Model.Health;
        strip.Children.Clear();
        strip.ColumnDefinitions.Clear();
        var cells = new (string Label, Color Dot, string Value, string Caption)[]
        {
            ("Health", score >= 80 ? Theme.Good : score >= 60 ? Theme.Amber : Theme.Red, $"{score}",
             score >= 80 ? "Running smooth" : score >= 60 ? "Could use a tidy-up" : "Needs attention"),
            ("CPU", Theme.Level(s.Cpu), $"{Math.Round(s.Cpu * 100)}%", "All cores"),
            ("Memory", Theme.Level(s.Ram), Format.Memory(s.RamUsed), $"of {Format.Memory(s.RamTotal)}"),
            ("Network", Theme.Accent2, "↓ " + Format.Rate(s.Download), "↑ " + Format.Rate(s.Upload)),
            ("Disk", Theme.Level(s.Disk), $"{Math.Round(s.Disk * 100)}%", s.DiskFree > 0 ? $"{Format.Bytes(s.DiskFree)} free" : "used"),
        };
        for (var i = 0; i < cells.Length; i++)
        {
            strip.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var c = cells[i];
            var cell = Stat(c.Label, c.Value, c.Caption, c.Dot);
            cell.Padding = new Thickness(S(12), S(9), S(12), S(9));
            var border = new Border
            {
                Child = cell,
                BorderBrush = Theme.Brush(Theme.Stroke),
                BorderThickness = new Thickness(i == 0 ? 0 : 1, 0, 0, 0),
            };
            Grid.SetColumn(border, i);
            strip.Children.Add(border);
        }
    }

    private void Cleanup()
    {
        var c = Model.Cleaner;
        cleanup.Children.Clear();
        var subtitle = c.LastRun is { } last ? $"Sorted by size · last run {last:HH.mm}" : "Sorted by size · never cleaned";
        var freeLabel = c.Cleaning is not null ? "Cleaning…" : $"Free {Format.Bytes(c.Total)}";
        var free = Plain(Text(freeLabel, 10, Theme.Background, FontWeights.SemiBold), () => _ = c.CleanAsync(CleanKind.All),
                         Theme.Ink, 12, new Thickness(S(12), S(4), S(12), S(4)));
        free.IsEnabled = c.Cleaning is null && c.Total > 0;
        free.Opacity = c.Total == 0 ? 0.5 : 1;
        cleanup.Children.Add(Columns(6, (V(2, Text("Cleanup", 13, weight: FontWeights.SemiBold), Text(subtitle, 9, Theme.Faint)), 1), (free, null)));
        cleanup.Children.Add(CleanRow(Theme.Amber, "Temp & junk", "Reclaimable", "Temp files older than a day",
                                      Format.Bytes(c.TempBytes), "Clean", c.TempBytes > 0, () => _ = c.CleanAsync(CleanKind.Temp)));
        cleanup.Children.Add(Divider());
        cleanup.Children.Add(CleanRow(Theme.Accent2, "Browser cache", c.FoundBrowsers.Count > 0 ? string.Join(" · ", c.FoundBrowsers.Take(2)) : null,
                                      "Web pages and images saved by browsers", Format.Bytes(c.BrowserBytes), "Clean", c.BrowserBytes > 0,
                                      () => _ = c.CleanAsync(CleanKind.Browser)));
        cleanup.Children.Add(Divider());
        cleanup.Children.Add(CleanRow(Theme.Red, "Downloads", null, "Open the folder to tidy old installers", null, "Open", true,
                                      () => _ = Windows.System.Launcher.LaunchFolderPathAsync(
                                          Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads"))));
    }

    private static Grid CleanRow(Color bar, string title, string? tag, string detail, string? figure, string action, bool enabled, Action perform)
    {
        var stripe = new Border { Width = S(3), Height = S(28), CornerRadius = new CornerRadius(S(1.5)), Background = Theme.Brush(bar) };
        var heading = H(6, Text(title, 11, weight: FontWeights.Medium), tag is null ? null : Pill(tag, bar));
        var texts = V(2, heading, Text(detail, 9, Theme.Faint));
        Border? amount = figure is null ? null : new Border
        {
            Child = Text(figure, 9.5, mono: true),
            Padding = new Thickness(S(7), S(2), S(7), S(2)),
            CornerRadius = new CornerRadius(S(6)),
            Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.06)),
            VerticalAlignment = VerticalAlignment.Center,
        };
        var button = Plain(Text(action, 9.5, weight: FontWeights.Medium), perform, Theme.WithAlpha(Theme.Ink, 0.09), 11,
                           new Thickness(S(10), S(3), S(10), S(3)));
        button.IsEnabled = enabled;
        button.Opacity = enabled ? 1 : 0.4;
        var row = Columns(10, (stripe, null), (texts, 1), (amount, null), (button, null));
        row.Padding = new Thickness(0, S(3), 0, S(3));
        return row;
    }

    private void Quick()
    {
        var s = Model.Settings;
        quick.Children.Clear();
        var on = new[] { s.ClipboardHistory, s.ScreenshotsToShelf, s.Lyrics }.Count(x => x);
        quick.Children.Add(V(2, Text("Quick settings", 13, weight: FontWeights.SemiBold), Text($"3 switches · {on} on", 9, Theme.Faint)));
        quick.Children.Add(Row(null, "Clipboard history", "100 items · memory", Switch(s.ClipboardHistory, v => { s.ClipboardHistory = v; Save(); })));
        quick.Children.Add(Row(null, "Screenshots to Shelf", "Pictures › Screenshots", Switch(s.ScreenshotsToShelf, v => { s.ScreenshotsToShelf = v; Save(); })));
        quick.Children.Add(Row(null, "Lyrics", "LRCLIB · free", Switch(s.Lyrics, v => { s.Lyrics = v; Save(); })));
    }

    private void Save()
    {
        Model.Settings.Save();
        Quick();
    }
}
