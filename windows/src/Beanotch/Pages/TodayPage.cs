using System.Globalization;
using Beanotch.Core;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI;
using Microsoft.UI.Xaml.Input;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Today: weather, the next event, tasks and focus across the top; the agenda, tasks or month on the left; focus
// timer, countdown timer or world clocks on the right.
public sealed class TodayPage(Model model, Action<Tab> open) : PanelPage(model)
{
    private readonly Grid strip = new();
    private readonly Grid left = new();
    private readonly Grid right = new();
    // Which tab the left card opens on; the CI snapshots set it to show Rates.
    internal static int StartLeft;
    private int leftMode = StartLeft, rightMode;
    private readonly TextBox taskInput = new() { PlaceholderText = "Add a task · \"call Budi 15.00\" sets a reminder" };
    private TextBlock? bigTime;

    protected override FrameworkElement Build()
    {
        taskInput.FontSize = S(10.5);
        taskInput.KeyDown += OnTaskKey;
        var leftCard = Card(left, 12, 12);
        var rightCard = Card(right, 12, 12);
        rightCard.Width = S(250);
        return Rows(10, (Card(strip, 0, 12), null), (Columns(10, (leftCard, 1), (rightCard, null)), 1));
    }

    public override void Refresh()
    {
        Strip();
        Left();
        Right();
        _ = Model.RefreshDataAsync().ContinueWith(_ => Dispatch(() => { Strip(); if (leftMode == 0) Left(); }), TaskScheduler.Default);
    }

    public override void Tick()
    {
        if (rightMode == 0) FocusTick();
        if (rightMode == 1) TimerTick();
    }

    // Top strip

    private void Strip()
    {
        var w = Model.Weather;
        var tasksLeft = Model.Settings.Tasks.Count(t => !t.Done);
        var next = Model.NextEvent;
        var focus = Model.Focus;
        var cells = new (string, string, string, Windows.UI.Color)[]
        {
            (Model.Settings.Place.Name, w is null ? "—" : $"{Math.Round(w.Temp)}°",
             w is null ? "Weather loads when online" : $"{Core.Weather.Describe(w.Code)} · H {Math.Round(w.High)}° L {Math.Round(w.Low)}°", Theme.Accent2),
            ("Next event", next is null ? "—" : next.Title,
             next is null ? (Model.Settings.CalendarUrl.Length == 0 ? "Calendar not connected" : "Nothing coming up")
                          : $"{When(next.Start)} · {Model.Clock(next.Start)}", Theme.Accent),
            ("Tasks", tasksLeft == 0 ? "All done" : $"{tasksLeft} left", tasksLeft == 0 ? "Nothing on the list" : Model.Settings.Tasks.First(t => !t.Done).Title, Theme.Amber),
            ("Focus", Clock(focus.Left), focus.Running ? (focus.OnBreak ? "On a break" : "Focusing") : $"Ready · {focus.Preset.Label}", Theme.Good),
        };
        strip.Children.Clear();
        strip.ColumnDefinitions.Clear();
        for (var i = 0; i < cells.Length; i++)
        {
            strip.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var (label, value, caption, dot) = cells[i];
            var cell = Stat(label, value, caption, dot);
            cell.Padding = new Thickness(S(12), S(9), S(12), S(9));
            var border = new Border { Child = cell, BorderBrush = Theme.Brush(Theme.Stroke), BorderThickness = new Thickness(i == 0 ? 0 : 1, 0, 0, 0) };
            Grid.SetColumn(border, i);
            strip.Children.Add(border);
        }
    }

    // Left card

    private void Left()
    {
        left.Children.Clear();
        var subtitle = leftMode switch { 0 => "Calendar · next 24 hours", 1 => "Saved on this PC", 2 => DateTime.Now.ToString("MMMM yyyy"), _ => "In " + Rates.Local };
        // Four tabs leave the title no room beside them, so they get a row of their own.
        var head = V(8, Columns(8, (Text(leftMode == 3 ? "Rates" : "Up next", 13, weight: FontWeights.SemiBold), null), (Text(subtitle, 9, Theme.Faint), 1)),
                     Segmented(["Agenda", "Tasks", "Month", "Rates"], leftMode, i => { leftMode = i; Left(); }));
        FrameworkElement body = leftMode switch { 0 => Agenda(), 1 => Tasks(), 2 => Month(), _ => RatesView() };
        left.Children.Add(Rows(10, (head, null), (body, 1)));
    }

    // Exchange rates and gold, in the local currency, three to a row, with the change since yesterday.
    private FrameworkElement RatesView()
    {
        var rates = Model.Rates;
        if (rates.PerDollar.Count == 0)
        {
            _ = rates.RefreshAsync().ContinueWith(_ => Dispatch(() => { if (leftMode == 3) Left(); }), TaskScheduler.Default);
            return Text("Getting today's rates…", 10, Theme.Faint);
        }
        FrameworkElement Cell(string code, double? value, double? change, string unit = "")
        {
            var tint = code == "Gold" ? Theme.Amber : Rates.Fuels.Contains(code.ToUpperInvariant()) ? Theme.Accent2 : Theme.Accent;
            var top = Columns(4, (Text(code + unit, 8.5, tint, FontWeights.Bold), 1),
                              (change is { } c ? Text((c >= 0 ? "▲" : "▼") + Math.Abs(c * 100).ToString("0.0") + "%", 8, c >= 0 ? Theme.Good : Theme.Red, FontWeights.SemiBold) : null, null));
            return new Border
            {
                Child = V(2, top, Text(value is { } v ? Rates.Format(v, Rates.Local) : "–", 11, weight: FontWeights.SemiBold)),
                Padding = new Thickness(S(8), S(6), S(8), S(6)),
                CornerRadius = new CornerRadius(S(9)),
                Background = Theme.Brush(Theme.WithAlpha(tint, 0.06)),
            };
        }
        var cells = Rates.Watched.Select(c => Cell(c, rates.Value(c), rates.Change(c, rates.Value(c))))
            .Append(Cell("Gold", rates.GoldGram, rates.Change("gold", rates.GoldGram), " / g"))
            .Concat(Rates.Fuels.Where(rates.Fuel.ContainsKey).Select(f => Cell(f[..1] + f[1..].ToLowerInvariant(), rates.Fuel[f], rates.Change(f, rates.Fuel[f]), " / L"))).ToList();
        var grid = new Grid { ColumnSpacing = S(6), RowSpacing = S(6) };
        for (var c = 0; c < 3; c++) grid.ColumnDefinitions.Add(new ColumnDefinition());
        for (var r = 0; r < 2; r++) grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        for (var i = 0; i < cells.Count && i < 6; i++)
        {
            Grid.SetColumn(cells[i], i % 3);
            Grid.SetRow(cells[i], i / 3);
            grid.Children.Add(cells[i]);
        }
        return grid;
    }

    private FrameworkElement Agenda()
    {
        if (Model.Settings.CalendarUrl.Length == 0)
        {
            var connect = Card(V(8, Columns(10, (Icon(Glyphs.Calendar, 16, Theme.Accent), null), (Text("Connect your calendar", 12, weight: FontWeights.SemiBold), 1)),
                Text("Paste its secret iCal address from Google Calendar or Outlook in Settings.", 9.5, Theme.Dim, wrap: true),
                PillButton("Connect", Theme.Accent, () => open(Tab.Settings))), 12, 10);
            return connect;
        }
        var now = DateTimeOffset.Now;
        var soon = Model.Events.Where(e => e.End > now && e.Start < now.AddHours(24)).Take(6).ToList();
        if (soon.Count == 0) return Text(Model.CalendarFailed ? "Couldn't read the calendar address" : "Nothing in the next 24 hours", 10.5, Theme.Faint);
        var list = V(6);
        foreach (var e in soon)
        {
            var live = e.Start <= now;
            var time = Text(e.AllDay ? "All day" : Model.Clock(e.Start), 10, live ? Theme.Accent : Theme.Dim, FontWeights.SemiBold, mono: true);
            time.Width = S(48);
            var texts = V(1, Text(e.Title, 11, weight: FontWeights.SemiBold), e.Location is null ? null : Text(e.Location, 8.5, Theme.Faint));
            var join = e.Link is null ? null : PillButton(live ? "Join now" : "Join", Theme.Accent, () => Controls.Launch(e.Link));
            list.Children.Add(Columns(10, (time, null), (texts, 1), (join, null)));
        }
        return Scroll(list);
    }

    private FrameworkElement Tasks()
    {
        var list = V(4);
        foreach (var task in Model.Settings.Tasks.OrderBy(t => t.Done).ToList())
        {
            var check = new CheckBox { IsChecked = task.Done, MinWidth = 0, Padding = new Thickness(0) };
            check.Checked += (_, _) => { task.Done = true; SaveTasks(); };
            check.Unchecked += (_, _) => { task.Done = false; SaveTasks(); };
            var title = Text(task.Title, 11, task.Done ? Theme.Faint : Theme.Ink, FontWeights.Medium);
            var when = task.Remind is { } at ? Text(Model.Clock(at), 9, task.Reminded ? Theme.Faint : Theme.Amber, mono: true) : null;
            var remove = IconButton(Glyphs.Close, () => { Model.Settings.Tasks.Remove(task); SaveTasks(); }, 7, Theme.Faint, "Remove", 20);
            list.Children.Add(Columns(6, (check, null), (title, 1), (when, null), (remove, null)));
        }
        if (Model.Settings.Tasks.Count == 0) list.Children.Add(Text("Nothing on the list", 10.5, Theme.Faint));
        return Rows(8, (Detach(taskInput), null), (Scroll(list), 1));
    }

    private void OnTaskKey(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != Windows.System.VirtualKey.Enter) return;
        var text = taskInput.Text.Trim();
        if (text.Length == 0) return;
        var task = new TaskItem { Title = text };
        // A trailing time ("15.00", "9:30") becomes a reminder today, or tomorrow if it has passed.
        var words = text.Split(' ');
        if (words.Length > 1 && TimeOnly.TryParseExact(words[^1].Replace(':', '.'), ["H.mm", "HH.mm"], CultureInfo.InvariantCulture, DateTimeStyles.None, out var t))
        {
            var at = new DateTimeOffset(DateTime.Today.Add(t.ToTimeSpan()));
            if (at < DateTimeOffset.Now) at = at.AddDays(1);
            task.Title = string.Join(' ', words[..^1]);
            task.Remind = at;
        }
        Model.Settings.Tasks.Add(task);
        taskInput.Text = "";
        SaveTasks();
    }

    private void SaveTasks()
    {
        Model.Settings.Save();
        Strip();
        Left();
    }

    private FrameworkElement Month()
    {
        var today = DateTime.Today;
        var first = new DateTime(today.Year, today.Month, 1);
        var grid = new Grid { RowSpacing = S(2), ColumnSpacing = S(2) };
        for (var c = 0; c < 7; c++) grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var offset = ((int)first.DayOfWeek + 6) % 7; // weeks start on Monday
        var days = DateTime.DaysInMonth(today.Year, today.Month);
        var rows = (offset + days + 6) / 7 + 1;
        for (var r = 0; r < rows; r++) grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        string[] names = ["M", "T", "W", "T", "F", "S", "S"];
        for (var c = 0; c < 7; c++) Place(grid, Center(Text(names[c], 8.5, Theme.Faint, FontWeights.SemiBold)), 0, c);
        var busy = Model.Events.Select(e => e.Start.LocalDateTime.Date).ToHashSet();
        for (var d = 1; d <= days; d++)
        {
            var index = offset + d - 1;
            var date = new DateTime(today.Year, today.Month, d);
            var isToday = date == today;
            var label = Center(Text($"{d}", 10, isToday ? Theme.Background : date < today ? Theme.Faint : Theme.Ink, isToday ? FontWeights.Bold : FontWeights.Medium));
            var cell = new Grid { Height = S(22), CornerRadius = new CornerRadius(S(6)), Background = Theme.Brush(isToday ? Theme.Accent : Ui.Ui.Transparent) };
            cell.Children.Add(label);
            if (busy.Contains(date))
                cell.Children.Add(new Border { Width = S(4), Height = S(4), CornerRadius = new CornerRadius(S(2)), Background = Theme.Brush(isToday ? Theme.Background : Theme.Accent2),
                                               VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness(0, 0, 0, S(1)) });
            Place(grid, cell, index / 7 + 1, index % 7);
        }
        return grid;
    }

    private static void Place(Grid grid, FrameworkElement el, int row, int column)
    {
        Grid.SetRow(el, row);
        Grid.SetColumn(el, column);
        grid.Children.Add(el);
    }

    // Right card

    private void Right()
    {
        right.Children.Clear();
        bigTime = null;
        var tabs = Segmented(["Focus", "Timer", "Clocks"], rightMode, i => { rightMode = i; Right(); });
        FrameworkElement body = rightMode switch { 0 => FocusView(), 1 => TimerView(), _ => ClocksView() };
        right.Children.Add(Rows(10, (tabs, null), (body, 1)));
    }

    // The ring on the left fills as the stretch runs, with play/pause in its middle; beside it the time, the phase and
    // when it ends, then the lengths and a jump between focus and a break. Focus burns orange to red, the break cools
    // to blue, as on the Mac.
    private FrameworkElement FocusView()
    {
        var focus = Model.Focus;
        var resting = focus.OnBreak;
        bigTime = Text(Clock(focus.Left), 24, weight: FontWeights.Bold, display: true);
        var phase = resting ? "Break" : "Focus";
        var state = focus.Running ? "ends " + (DateTime.Now + focus.Left).ToString("t")
                  : focus.Left < focus.Total ? "paused" : $"{(int)focus.Total.TotalMinutes} min";
        var (from, to) = resting ? (Theme.Rgb(0.3, 0.62, 1), Theme.Rgb(0.12, 0.4, 0.86)) : (Theme.Rgb(1, 0.5, 0.16), Theme.Rgb(0.9, 0.27, 0.16));
        var dial = Dial(from, to, focus.Running ? Glyphs.Pause : Glyphs.Play, focus.Running ? "Pause" : "Start", () => { focus.Toggle(); Right(); });

        // The lengths and a reset behind the gear, so the page fits short panels too.
        var lengths = new MenuFlyout();
        for (var i = 0; i < FocusPreset.All.Length; i++)
        {
            var index = i;
            var p = FocusPreset.All[i];
            var item = new ToggleMenuFlyoutItem { Text = $"{p.Work} min focus, {p.Rest} min break", IsChecked = p == focus.Preset };
            item.Click += (_, _) =>
            {
                focus.Choose(FocusPreset.All[index]);
                Model.Settings.FocusPreset = index;
                Model.Settings.Save();
                Right();
            };
            lengths.Items.Add(item);
        }
        lengths.Items.Add(new MenuFlyoutSeparator());
        var sounds = new MenuFlyoutSubItem { Text = "Sound while focusing" };
        foreach (var name in new[] { "" }.Concat(Enum.GetNames<AmbientSound>()))
        {
            var item = new ToggleMenuFlyoutItem
            {
                Text = name.Length == 0 ? "None" : Ambient.Title(Enum.Parse<AmbientSound>(name)),
                IsChecked = Model.Settings.FocusSound == name,
            };
            item.Click += (_, _) => { Model.Settings.FocusSound = name; Model.Settings.Save(); Right(); };
            sounds.Items.Add(item);
        }
        lengths.Items.Add(sounds);
        lengths.Items.Add(new MenuFlyoutSeparator());
        var reset = new MenuFlyoutItem { Text = "Reset" };
        reset.Click += (_, _) => { focus.Reset(); Right(); };
        lengths.Items.Add(reset);
        var gear = new Button
        {
            Content = Icon(Glyphs.Settings, 11),
            Width = S(24),
            Height = S(24),
            Padding = new Thickness(0),
            CornerRadius = new CornerRadius(S(12)),
            Background = Theme.Brush(Ui.Ui.Transparent),
            BorderBrush = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.18)),
            BorderThickness = new Thickness(1),
            Flyout = lengths,
        };
        ToolTipService.SetToolTip(gear, "Lengths and reset");
        var pill = Plain(Text(resting ? "Focus" : "Break", 9.5, weight: FontWeights.SemiBold), () => { focus.Skip(); Right(); },
                         Theme.WithAlpha(Theme.Ink, 0.1), 12, new Thickness(S(12), S(4), S(12), S(4)), resting ? "Back to focus" : "Take a break now");
        FocusTick();
        return Columns(12, (dial, null), (Side(from, $"{phase} · {state}", H(6, gear, pill)), 1));
    }

    // The time beside the ring: large, then a dot and a status line, then the controls at the bottom.
    private Grid Side(Color dot, string status, UIElement controls)
    {
        var mark = new Microsoft.UI.Xaml.Shapes.Ellipse { Width = S(6), Height = S(6), Fill = Theme.Brush(dot), VerticalAlignment = VerticalAlignment.Center };
        return Rows(2, (bigTime, null), (H(5, mark, Text(status, 8.5, Theme.Dim, FontWeights.Medium)), null), (null, 1), (controls, null));
    }

    // A ring of progress with one round button in its middle, for Focus and Timer. The ring is filled in on each tick.
    private Grid Dial(Color from, Color to, string glyph, string tip, Action onClick)
    {
        var button = new Button
        {
            Content = Icon(glyph, 14, Theme.Ink),
            Width = S(40),
            Height = S(40),
            Padding = new Thickness(0),
            CornerRadius = new CornerRadius(S(20)),
            Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.08)),
            BorderThickness = new Thickness(0),
        };
        button.Click += (_, _) => onClick();
        ToolTipService.SetToolTip(button, tip);
        ring = new Microsoft.UI.Xaml.Shapes.Path
        {
            StrokeThickness = S(RingStroke),
            StrokeStartLineCap = Microsoft.UI.Xaml.Media.PenLineCap.Round,
            StrokeEndLineCap = Microsoft.UI.Xaml.Media.PenLineCap.Round,
            Stroke = new Microsoft.UI.Xaml.Media.LinearGradientBrush
            {
                StartPoint = new Windows.Foundation.Point(0, 0),
                EndPoint = new Windows.Foundation.Point(1, 1),
                GradientStops = { new() { Color = from, Offset = 0 }, new() { Color = to, Offset = 1 } },
            },
        };
        var track = new Microsoft.UI.Xaml.Shapes.Ellipse { Stroke = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.1)), StrokeThickness = S(RingStroke) };
        return new Grid { Width = S(RingSide), Height = S(RingSide), Children = { track, ring, Center(button) }, VerticalAlignment = VerticalAlignment.Center };
    }

    private const double RingSide = 94, RingStroke = 4.5;
    private Microsoft.UI.Xaml.Shapes.Path? ring;

    private void FocusTick()
    {
        if (bigTime is null || ring is null) return;
        var focus = Model.Focus;
        bigTime.Text = Clock(focus.Left);
        ring.Data = Arc(Math.Clamp(focus.Progress, 0.002, 0.9999), S(RingSide), S(RingStroke));
    }

    // An arc from twelve o'clock, clockwise, for the share of the stretch that has passed.
    private static Microsoft.UI.Xaml.Media.PathGeometry Arc(double share, double size, double stroke)
    {
        var r = (size - stroke) / 2;
        var c = size / 2;
        var angle = share * 2 * Math.PI;
        var figure = new Microsoft.UI.Xaml.Media.PathFigure { StartPoint = new Windows.Foundation.Point(c, c - r), IsClosed = false };
        figure.Segments.Add(new Microsoft.UI.Xaml.Media.ArcSegment
        {
            Point = new Windows.Foundation.Point(c + r * Math.Sin(angle), c - r * Math.Cos(angle)),
            Size = new Windows.Foundation.Size(r, r),
            SweepDirection = Microsoft.UI.Xaml.Media.SweepDirection.Clockwise,
            IsLargeArc = share > 0.5,
        });
        var geometry = new Microsoft.UI.Xaml.Media.PathGeometry();
        geometry.Figures.Add(figure);
        return geometry;
    }

    // The ring and the time beside it, as in Focus. The ring empties as the countdown runs; the menu picks the length.
    private FrameworkElement TimerView()
    {
        var timer = Model.Timer;
        bigTime = Text(Clock(timer.Left), 24, weight: FontWeights.Bold, display: true);
        Color from = Theme.Rgb(0.25, 0.8, 0.9), to = Theme.Rgb(0.3, 0.55, 1);
        var dial = Dial(from, to, timer.Running ? Glyphs.Pause : Glyphs.Play, timer.Running ? "Pause" : "Start", () => { timer.Toggle(); Right(); });
        var status = timer.Running ? "Ends " + (DateTime.Now + timer.Left).ToString("t")
                   : timer.Left < timer.Length ? "Paused" : "Shows in the island";

        var lengths = new MenuFlyout();
        foreach (var m in CountdownTimer.Presets)
        {
            var item = new ToggleMenuFlyoutItem { Text = $"{m} min", IsChecked = timer.Length.TotalMinutes == m };
            item.Click += (_, _) => { timer.Set(m); Right(); };
            lengths.Items.Add(item);
        }
        var pick = new Button
        {
            Content = H(4, Text($"{(int)timer.Length.TotalMinutes} min", 9.5, weight: FontWeights.SemiBold), Icon(Glyphs.ChevronDown, 7, Theme.Ink)),
            Padding = new Thickness(S(12), S(4), S(12), S(4)),
            CornerRadius = new CornerRadius(S(12)),
            Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.1)),
            BorderThickness = new Thickness(0),
            Flyout = lengths,
        };
        ToolTipService.SetToolTip(pick, "Length");
        TimerTick();
        return Columns(12, (dial, null), (Side(from, status, pick), 1));
    }

    private void TimerTick()
    {
        if (bigTime is null || ring is null) return;
        var timer = Model.Timer;
        bigTime.Text = Clock(timer.Left);
        ring.Data = Arc(Math.Clamp(timer.Left / timer.Length, 0.002, 0.9999), S(RingSide), S(RingStroke));
    }

    private FrameworkElement ClocksView()
    {
        var list = V(8);
        var local = DateTimeOffset.Now;
        foreach (var id in Model.Settings.Clocks)
        {
            TimeZoneInfo zone;
            try { zone = TimeZoneInfo.FindSystemTimeZoneById(id); }
            catch (Exception) { continue; }
            var there = TimeZoneInfo.ConvertTime(local, zone);
            var diff = there.Offset - local.Offset;
            var city = id.Split('/').Last().Replace('_', ' ');
            var caption = diff == TimeSpan.Zero ? "Same time" : $"{(diff > TimeSpan.Zero ? "+" : "−")}{Math.Abs(diff.TotalHours):0.#}h · {there:ddd}";
            list.Children.Add(Columns(8, (V(1, Text(city, 11, weight: FontWeights.SemiBold), Text(caption, 8.5, Theme.Faint)), 1),
                                      (Text(there.ToString("HH.mm", CultureInfo.InvariantCulture), 16, weight: FontWeights.Bold, display: true), null)));
        }
        list.Children.Add(Text("Change the cities in Settings › Today", 8.5, Theme.Faint));
        return Scroll(list);
    }

    private static string When(DateTimeOffset t)
    {
        var day = t.LocalDateTime.Date;
        return day == DateTime.Today ? "Today" : day == DateTime.Today.AddDays(1) ? "Tomorrow" : t.LocalDateTime.ToString("ddd d MMM");
    }

    private static string Clock(TimeSpan t) => t.TotalHours >= 1 ? t.ToString(@"h\:mm\:ss") : t.ToString(@"mm\:ss");
}
