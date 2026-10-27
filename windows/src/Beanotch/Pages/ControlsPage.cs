using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.System.Power;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Controls: system switches as tiles, brightness per screen, the battery, and one-click actions (Windows has no
// Shortcuts app, so these stand in for the Mac's Shortcuts card).
public sealed class ControlsPage(Model model) : PanelPage(model)
{
    private readonly Grid tiles = new() { ColumnSpacing = S(6) };
    private readonly StackPanel brightness = V(6);
    private readonly StackPanel battery = V(4);
    private readonly Grid actions = new() { RowSpacing = S(6), ColumnSpacing = S(6) };
    private List<Display>? displays;
    private DateTime displaysAt;

    protected override FrameworkElement Build()
    {
        var bright = Card(V(8, Text("Brightness", 13, weight: FontWeights.SemiBold), brightness), 12, 12);
        var power = Card(V(8, Text("Battery", 13, weight: FontWeights.SemiBold), battery), 12, 12);
        var quick = Card(V(8, Text("Quick actions", 13, weight: FontWeights.SemiBold), actions), 12, 12);
        quick.Width = S(230);
        BuildActions();
        return Scroll(V(10, tiles, Columns(10, (V(10, bright, power), 1), (quick, null))));
    }

    public override void Refresh()
    {
        Tiles();
        Battery();
        if (displays is null || DateTime.UtcNow - displaysAt > TimeSpan.FromSeconds(30))
        {
            brightness.Children.Clear();
            brightness.Children.Add(Text("Looking for screens…", 10, Theme.Faint));
            _ = Task.Run(Brightness.Read).ContinueWith(t => Dispatch(() =>
            {
                displays = t.IsCompletedSuccessfully ? t.Result : [];
                displaysAt = DateTime.UtcNow;
                Sliders();
            }), TaskScheduler.Default);
        }
        else Sliders();
    }

    private void Tiles()
    {
        var items = new (string Glyph, string Title, Func<bool> Get, Action<bool> Set)[]
        {
            ("", "Dark mode", () => Controls.DarkMode, v => Controls.DarkMode = v),
            ("", "Keep awake", () => Controls.KeepAwake, v => Controls.KeepAwake = v),
            (Glyphs.Mic, "Mic muted", () => Controls.MicMuted, v => Controls.MicMuted = v),
            ("", "Hide taskbar", () => Controls.TaskbarHidden, v => Controls.TaskbarHidden = v),
            ("", "Desktop icons", () => Controls.DesktopIcons, v => Controls.DesktopIcons = v),
            ("", "Hidden files", () => Controls.HiddenFiles, v => Controls.HiddenFiles = v),
        };
        tiles.Children.Clear();
        tiles.ColumnDefinitions.Clear();
        for (var i = 0; i < items.Length; i++)
        {
            var (glyph, title, get, set) = items[i];
            bool on;
            try { on = get(); } catch (Exception) { on = false; }
            var label = Text(title, 10, weight: FontWeights.SemiBold, wrap: true);
            label.MaxLines = 2;
            var body = V(4, Icon(glyph, 12, on ? Theme.Accent : Theme.Dim), label, Text(on ? "On" : "Off", 8.5, on ? Theme.Accent : Theme.Faint));
            body.Padding = new Thickness(S(8));
            var tile = Plain(body, () =>
            {
                try { set(!on); } catch (Exception) { }
                Tiles();
            }, on ? Theme.WithAlpha(Theme.Accent, 0.14) : Theme.Surface, 12);
            tile.HorizontalAlignment = HorizontalAlignment.Stretch;
            tile.BorderThickness = new Thickness(1);
            tile.BorderBrush = Theme.Brush(on ? Theme.WithAlpha(Theme.Accent, 0.6) : Theme.Stroke);
            tiles.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetColumn(tile, i);
            tiles.Children.Add(tile);
        }
    }

    private void Sliders()
    {
        brightness.Children.Clear();
        if (displays is null || displays.Count == 0)
        {
            brightness.Children.Add(Text("No screen here takes brightness from apps", 10, Theme.Faint));
            return;
        }
        foreach (var display in displays)
        {
            var slider = new Slider { Minimum = 0, Maximum = 100, Value = display.Level, StepFrequency = 1 };
            slider.Resources["SliderTrackValueFill"] = Theme.Brush(Theme.Accent);
            var value = Text($"{display.Level}", 9.5, Theme.Faint, mono: true);
            value.Width = S(26);
            CancellationTokenSource? pending = null;
            slider.ValueChanged += (_, e) =>
            {
                value.Text = $"{(int)e.NewValue}";
                // Settle for a moment before writing: each write is a WMI or DDC/CI round trip.
                pending?.Cancel();
                pending = new CancellationTokenSource();
                var token = pending.Token;
                var level = (int)e.NewValue;
                _ = Task.Delay(250, token).ContinueWith(_ => Brightness.Set(display, level), token, TaskContinuationOptions.OnlyOnRanToCompletion, TaskScheduler.Default);
            };
            var name = Text(display.Name, 10.5, weight: FontWeights.Medium);
            name.Width = S(130);
            brightness.Children.Add(Columns(10, (Icon(display.BuiltIn ? "" : "", 11, Theme.Dim), null), (name, null), (slider, 1), (value, null)));
        }
    }

    private void Battery()
    {
        battery.Children.Clear();
        try
        {
            if (PowerManager.BatteryStatus == BatteryStatus.NotPresent)
            {
                battery.Children.Add(Text("This PC runs on mains power", 10, Theme.Faint));
                return;
            }
            var percent = PowerManager.RemainingChargePercent;
            var charging = PowerManager.PowerSupplyStatus != PowerSupplyStatus.NotPresent;
            var left = PowerManager.RemainingDischargeTime;
            var caption = charging ? "Plugged in" : left.TotalHours < 48 && left > TimeSpan.Zero ? $"{(int)left.TotalHours}h {left.Minutes}m left" : "On battery";
            battery.Children.Add(Columns(10, (Icon(charging ? Glyphs.Charging : Glyphs.Battery, 11, Theme.Dim), null),
                                         (V(1, Text("This PC", 10.5, weight: FontWeights.Medium), Text(caption, 8.5, Theme.Faint)), 1),
                                         (Text($"{percent}%", 11, Theme.Level(1 - percent / 100.0), FontWeights.SemiBold, mono: true), null)));
            battery.Children.Add(Bar(percent / 100.0, Theme.Level(1 - percent / 100.0), 4));
        }
        catch (Exception) { battery.Children.Add(Text("Battery details aren't available", 10, Theme.Faint)); }
    }

    private void BuildActions()
    {
        var items = new (string Glyph, string Title, Action Run)[]
        {
            ("", "Lock", Controls.Lock),
            ("", "Sleep", Controls.Sleep),
            (Glyphs.Screenshot, "Snip", Controls.Snip),
            (Glyphs.Delete, "Empty bin", Controls.EmptyRecycleBin),
            (Glyphs.Camera, "Camera", Controls.Camera),
            (Glyphs.Settings, "Settings", () => Controls.Settings()),
        };
        actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var i = 0; i < items.Length; i++)
        {
            if (i % 2 == 0) actions.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var (glyph, title, run) = items[i];
            var button = Plain(H(8, Icon(glyph, 11, Theme.Accent), Text(title, 10.5, weight: FontWeights.Medium)), run,
                               Theme.WithAlpha(Theme.Ink, 0.06), 9, new Thickness(S(10), S(8), S(10), S(8)));
            button.HorizontalAlignment = HorizontalAlignment.Stretch;
            Grid.SetRow(button, i / 2);
            Grid.SetColumn(button, i % 2);
            actions.Children.Add(button);
        }
    }
}
