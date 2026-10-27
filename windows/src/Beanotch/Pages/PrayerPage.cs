using Beanotch.Core;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Prayer times: the next prayer with the time since the last one, the qibla, the place, and the day's times as tiles.
public sealed class PrayerPage(Model model) : PanelPage(model)
{
    private readonly TextBlock nextName = Text("", 26, Theme.Accent, FontWeights.Bold, display: true);
    private readonly TextBlock nextTime = Text("", 15, weight: FontWeights.SemiBold);
    private readonly TextBlock countdown = Text("", 11, Theme.Dim, mono: true);
    private readonly Grid progress = new();
    private readonly TextBlock method = Text("", 9, Theme.Faint);
    private readonly TextBlock place = Text("", 12, weight: FontWeights.SemiBold);
    private readonly TextBlock qibla = Text("", 9.5, Theme.Dim);
    private readonly RotateTransform needle = new();
    private readonly Grid tiles = new() { ColumnSpacing = S(8) };
    private DateOnly day;

    protected override FrameworkElement Build()
    {
        var left = V(6, Text("NEXT PRAYER", 8.5, Theme.Faint, FontWeights.SemiBold), H(8, nextName, nextTime),
                     progress, Columns(8, (method, 1), (countdown, null)));
        left.Children[0].SetValue(TextBlock.CharacterSpacingProperty, 120);

        var arrow = Icon("\uE74A", 15, Theme.Accent);
        arrow.RenderTransform = needle;
        arrow.RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5);
        var dial = new Grid
        {
            Width = S(56),
            Height = S(56),
            CornerRadius = new CornerRadius(S(28)),
            BorderBrush = Theme.Brush(Theme.Stroke),
            BorderThickness = new Thickness(1),
            Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.03)),
        };
        var north = Text("N", 7, Theme.Faint, FontWeights.SemiBold);
        north.HorizontalAlignment = HorizontalAlignment.Center;
        north.VerticalAlignment = VerticalAlignment.Top;
        north.Margin = new Thickness(0, S(3), 0, 0);
        dial.Children.Add(north);
        dial.Children.Add(Center(arrow));

        var picker = new ComboBox { ItemsSource = PrayerTimes.Cities.Select(c => c.Name).ToList(), SelectedItem = Model.Settings.City, FontSize = S(10) };
        picker.SelectionChanged += (_, _) =>
        {
            if (picker.SelectedItem is not string city || city == Model.Settings.City) return;
            Model.Settings.City = city;
            Model.Settings.Save();
            day = default;
            Refresh();
        };
        var methods = new ComboBox
        {
            ItemsSource = Enum.GetValues<PrayerMethod>().Select(PrayerTimes.Title).ToList(),
            SelectedIndex = (int)Model.Settings.Method,
            FontSize = S(10),
        };
        methods.SelectionChanged += (_, _) =>
        {
            if (methods.SelectedIndex < 0) return;
            Model.Settings.Method = (PrayerMethod)methods.SelectedIndex;
            Model.Settings.Save();
            day = default;
            Refresh();
        };
        var where = V(4, H(5, Icon(Glyphs.Location, 9, Theme.Ink), place), qibla, H(6, picker, methods));
        var right = H(12, dial, where);

        var top = Card(Columns(16, (left, 1), (new Border { Width = 1, Background = Theme.Brush(Theme.Stroke) }, null), (right, null)), 12, 14);
        return Rows(10, (top, null), (tiles, 1));
    }

    public override void Refresh()
    {
        var settings = Model.Settings;
        place.Text = settings.Place.Name;
        var bearing = Qibla(settings.Place.Lat, settings.Place.Lng);
        needle.Angle = bearing;
        qibla.Text = $"Qibla {Math.Round(bearing)}° {Compass(bearing)}";
        method.Text = PrayerTimes.Title(settings.Method) + " · since the last prayer";
        day = DateOnly.FromDateTime(DateTime.Now);

        var entries = Model.PrayersToday;
        var next = Model.NextPrayer;
        tiles.Children.Clear();
        tiles.ColumnDefinitions.Clear();
        for (var i = 0; i < entries.Count; i++)
        {
            var e = entries[i];
            var isNext = e.Time == next.Time;
            var past = e.Time < DateTimeOffset.Now;
            var glyph = e.Name switch { "Imsak" or "Isya" => Glyphs.Moon, "Terbit" or "Maghrib" => "", _ => Glyphs.Sun };
            var body = Rows(0, (Icon(glyph, 11, isNext ? Theme.Accent : Theme.Dim), null), (null, 1),
                            (Text(e.Name, 9.5, isNext ? Theme.Accent : Theme.Dim, FontWeights.Medium), null),
                            (Text(Model.Clock(e.Time), 15, past && !isNext ? Theme.Faint : Theme.Ink, FontWeights.SemiBold, display: true), null));
            var tile = Card(body, 10, 12);
            tile.VerticalAlignment = VerticalAlignment.Stretch;
            if (isNext)
            {
                tile.Background = Theme.Brush(Theme.WithAlpha(Theme.Accent, 0.12));
                tile.BorderBrush = Theme.Brush(Theme.Accent);
            }
            tiles.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetColumn(tile, i);
            tiles.Children.Add(tile);
        }
        Tick();
    }

    public override void Tick()
    {
        if (DateOnly.FromDateTime(DateTime.Now) != day) { Refresh(); return; }
        var next = Model.NextPrayer;
        nextName.Text = next.Name;
        nextTime.Text = Model.Clock(next.Time);
        var now = DateTimeOffset.Now;
        countdown.Text = "in " + Model.Countdown(next.Time - now);

        // Segments fill as the time since the previous prayer runs towards the next.
        var previous = Model.PrayersToday.Where(e => e.IsPrayer && e.Time <= now).Select(e => e.Time).DefaultIfEmpty(new DateTimeOffset(now.Date, now.Offset)).Max();
        var share = (now - previous) / (next.Time - previous);
        progress.Children.Clear();
        progress.ColumnDefinitions.Clear();
        progress.ColumnSpacing = S(2);
        const int segments = 30;
        for (var i = 0; i < segments; i++)
        {
            progress.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var seg = new Border
            {
                Height = S(7),
                CornerRadius = new CornerRadius(S(1.5)),
                Background = Theme.Brush(i < share * segments ? Theme.Accent : Theme.WithAlpha(Theme.Ink, 0.08)),
            };
            Grid.SetColumn(seg, i);
            progress.Children.Add(seg);
        }
    }

    // Great-circle bearing to the Kaaba, in degrees from north.
    public static double Qibla(double lat, double lng)
    {
        const double kLat = 21.4225, kLng = 39.8262;
        double rad = Math.PI / 180, phi = lat * rad, kPhi = kLat * rad, dLambda = (kLng - lng) * rad;
        var y = Math.Sin(dLambda);
        var x = Math.Cos(phi) * Math.Tan(kPhi) - Math.Sin(phi) * Math.Cos(dLambda);
        return (Math.Atan2(y, x) / rad + 360) % 360;
    }

    private static string Compass(double bearing) =>
        new[] { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }[(int)Math.Round(bearing / 45) % 8];
}
