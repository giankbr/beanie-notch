using Beanotch.Core;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Prayer times as the sun's path across the day, as on the Mac: a dot for each time along an arc that rises at sunrise,
// peaks at noon and sets at Maghrib, the part gone by in the accent and the sun or the moon where now is. The next
// prayer and its countdown sit above, the place and the qibla in a corner, and every time under its dot.
public sealed class PrayerPage(Model model) : PanelPage(model)
{
    private readonly TextBlock nextName = Text("", 20, Theme.Accent, FontWeights.Bold, display: true);
    private readonly TextBlock countdown = Text("", 12, Theme.Dim, FontWeights.SemiBold);
    private readonly TextBlock sub = Text("", 9.5, Theme.Faint);
    private readonly TextBlock place = Text("", 10, weight: FontWeights.SemiBold);
    private readonly RotateTransform needle = new();
    private readonly Canvas arc = new();
    private readonly Grid arcHost = new();
    private readonly Grid labels = new();
    private DateOnly day;
    private string drawn = "";

    protected override FrameworkElement Build()
    {
        var arrow = Icon("\uE74A", 11, Theme.Accent);
        arrow.RenderTransform = needle;
        arrow.RenderTransformOrigin = new Windows.Foundation.Point(0.5, 0.5);
        var dial = new Grid
        {
            Width = S(32), Height = S(32), CornerRadius = new CornerRadius(S(16)),
            BorderBrush = Theme.Brush(Theme.Stroke), BorderThickness = new Thickness(1),
            Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.04)),
            Children = { Center(arrow) },
        };
        var picker = new ComboBox { ItemsSource = PrayerTimes.Cities.Select(c => c.Name).ToList(), SelectedItem = Model.Settings.City, FontSize = S(9.5) };
        picker.SelectionChanged += (_, _) =>
        {
            if (picker.SelectedItem is not string city || city == Model.Settings.City) return;
            Model.Settings.City = city;
            Model.Settings.Save();
            day = default;
            Refresh();
        };
        place.HorizontalAlignment = HorizontalAlignment.Right;
        picker.HorizontalAlignment = HorizontalAlignment.Right;
        var where = H(8, V(2, place, picker), dial);
        where.VerticalAlignment = VerticalAlignment.Top;
        var header = Columns(10, (V(1, H(7, nextName, countdown), sub), 1), (where, null));

        arcHost.Children.Add(arc);
        arcHost.SizeChanged += (_, _) => { drawn = ""; Draw(); };
        return Rows(6, (header, null), (arcHost, 1), (labels, null));
    }

    public override void Refresh()
    {
        var settings = Model.Settings;
        var bearing = Qibla(settings.Place.Lat, settings.Place.Lng);
        needle.Angle = bearing;
        place.Text = $"{settings.Place.Name} · Qibla {Math.Round(bearing)}° {Compass(bearing)}";
        day = DateOnly.FromDateTime(DateTime.Now);

        // Each time under its dot, in even columns, the next one lit and the ones gone by faded.
        var entries = Model.PrayersToday;
        var next = Model.NextPrayer;
        labels.Children.Clear();
        labels.ColumnDefinitions.Clear();
        for (var i = 0; i < entries.Count; i++)
        {
            var e = entries[i];
            var isNext = e.Time == next.Time;
            var name = Text(Model.Label(e), 8.5, isNext ? Theme.Accent : Theme.Dim, FontWeights.Medium);
            var time = Text(Model.Clock(e.Time), 11, isNext ? Theme.Ink : e.Time < DateTimeOffset.Now ? Theme.Faint : Theme.Ink, FontWeights.SemiBold);
            name.HorizontalAlignment = time.HorizontalAlignment = HorizontalAlignment.Center;
            var cell = V(0, name, time);
            labels.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetColumn(cell, i);
            labels.Children.Add(cell);
        }
        drawn = "";
        Tick();
    }

    public override void Tick()
    {
        if (DateOnly.FromDateTime(DateTime.Now) != day) { Refresh(); return; }
        var next = Model.NextPrayer;
        var now = DateTimeOffset.Now;
        nextName.Text = Model.Label(next);
        countdown.Text = "in " + Model.Countdown(next.Time - now);
        sub.Text = Model.Fasting(now) ?? $"{Model.Clock(next.Time)} · {PrayerTimes.Title(Model.Settings.Method)}";
        sub.Foreground = Theme.Brush(Model.Fasting(now) is null ? Theme.Faint : Theme.Accent2);
        Draw();
    }

    // The arc, drawn again each minute and when its room changes size. The times sit evenly across, so close ones
    // like Imsak and Fajr don't crowd, each as high as the sun is then.
    private void Draw()
    {
        double w = arcHost.ActualWidth, h = arcHost.ActualHeight;
        var now = DateTimeOffset.Now;
        var key = $"{w:0}x{h:0}@{now:HHmm}";
        if (w < 10 || h < 10 || key == drawn) return;
        drawn = key;
        arc.Children.Clear();
        var entries = Model.PrayersToday;
        var n = entries.Count;
        if (n < 2) return;
        double horizon = h * 0.74, lift = h * 0.64, dip = h * 0.2;
        var rise = entries.FirstOrDefault(e => e.Name == "Sunrise")?.Time;
        var set = entries.FirstOrDefault(e => e.Name == "Maghrib")?.Time;
        double X(double position) => (position + 0.5) / n * w;
        double Elevation(DateTimeOffset t)
        {
            if (rise is not { } r || set is not { } s || s <= r) return 0;
            if (t >= r && t <= s) return Math.Sin(Math.PI * (t - r).TotalSeconds / (s - r).TotalSeconds);
            var away = t < r ? (r - t).TotalSeconds : (t - s).TotalSeconds;
            return -Math.Min(1, away / 7200);
        }
        Windows.Foundation.Point At(double position)
        {
            int i = Math.Clamp((int)Math.Floor(position), 0, n - 1), j = Math.Min(i + 1, n - 1);
            var t = entries[i].Time + (entries[j].Time - entries[i].Time) * (position - i);
            var e = Elevation(t);
            return new(X(position), horizon - (e >= 0 ? e * lift : e * dip));
        }
        var k = entries.ToList().FindLastIndex(e => e.Time <= now);
        var nowAt = k < 0 ? 0 : k == n - 1 ? n - 1 : k + (now - entries[k].Time) / (entries[k + 1].Time - entries[k].Time);
        Polyline Path(double a, double b, Brush stroke, double thickness)
        {
            var line = new Polyline { Stroke = stroke, StrokeThickness = thickness, StrokeLineJoin = PenLineJoin.Round, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round };
            var steps = Math.Max(2, (int)((b - a) * 24));
            for (var s = 0; s <= steps; s++) line.Points.Add(At(a + (b - a) * s / steps));
            return line;
        }

        arc.Children.Add(new Line
        {
            X1 = 0, X2 = w, Y1 = horizon, Y2 = horizon, StrokeThickness = 1,
            Stroke = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.12)), StrokeDashArray = [3, 4],
        });
        arc.Children.Add(Path(0, n - 1, Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.16)), 2));
        if (nowAt > 0)
        {
            Brush gone = Theme.Gradient
                ? new LinearGradientBrush
                {
                    StartPoint = new(0, 0), EndPoint = new(1, 0),
                    GradientStops = { new() { Color = Theme.Accent, Offset = 0 }, new() { Color = Theme.Accent2, Offset = 1 } },
                }
                : Theme.Brush(Theme.Accent);
            arc.Children.Add(Path(0, nowAt, gone, 2.5));
        }
        var next = Model.NextPrayer;
        for (var i = 0; i < n; i++)
        {
            var c = At(i);
            var e = entries[i];
            if (e.Time == next.Time)
            {
                Dot(c, 9, Theme.WithAlpha(Theme.Accent, 0.2));
                Dot(c, 5, Theme.Accent);
            }
            else Dot(c, 3.2, e.Time < now ? Theme.WithAlpha(Theme.Accent, 0.7) : Theme.WithAlpha(Theme.Ink, e.IsPrayer ? 0.45 : 0.25));
        }
        // Now: the sun while it's up, the moon while it's down.
        var here = At(nowAt);
        var mark = Icon(here.Y <= horizon ? Glyphs.Sun : Glyphs.Moon, 12, Theme.Amber);
        Canvas.SetLeft(mark, here.X - S(7));
        Canvas.SetTop(mark, here.Y - S(22));
        arc.Children.Add(mark);

        void Dot(Windows.Foundation.Point c, double r, Windows.UI.Color color)
        {
            var dot = new Ellipse { Width = r * 2, Height = r * 2, Fill = Theme.Brush(color) };
            Canvas.SetLeft(dot, c.X - r);
            Canvas.SetTop(dot, c.Y - r);
            arc.Children.Add(dot);
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
