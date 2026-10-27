using System.Globalization;
using Beanotch.Core;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
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
    private int leftMode, rightMode;
    private readonly TextBox taskInput = new() { PlaceholderText = "Add a task · \"call Budi 15.00\" sets a reminder" };
    private TextBlock? bigTime;
    private Grid? focusBar;
    private FontIcon? startGlyph;
    private TextBlock? startLabel;

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
        if (rightMode == 1 && bigTime is not null) bigTime.Text = Clock(Model.Timer.Left);
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
        var subtitle = leftMode switch { 0 => "Calendar · next 24 hours", 1 => "Saved on this PC", _ => DateTime.Now.ToString("MMMM yyyy") };
        var head = Columns(8, (V(2, Text("Up next", 13, weight: FontWeights.SemiBold), Text(subtitle, 9, Theme.Faint)), 1),
                           (Segmented(["Agenda", "Tasks", "Month"], leftMode, i => { leftMode = i; Left(); }), null));
        FrameworkElement body = leftMode switch { 0 => Agenda(), 1 => Tasks(), _ => Month() };
        left.Children.Add(Rows(10, (head, null), (body, 1)));
    }

    private FrameworkElement Agenda()
    {
        if (Model.Settings.CalendarUrl.Length == 0)
        {
            var connect = Card(Columns(12, (Icon(Glyphs.Calendar, 18, Theme.Accent), null),
                (V(2, Text("Connect your calendar", 12, weight: FontWeights.SemiBold),
                      Text("Paste its secret iCal address (Google or Outlook) in Settings › Calendar", 9.5, Theme.Dim, wrap: true)), 1),
                (PillButton("Connect", Theme.Accent, () => open(Tab.Settings)), null)), 12, 10);
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

    private FrameworkElement FocusView()
    {
        var focus = Model.Focus;
        bigTime = Text(Clock(focus.Left), 34, weight: FontWeights.Bold, display: true);
        var mode = Text(focus.OnBreak ? "Break" : "Focus", 10, focus.OnBreak ? Theme.Good : Theme.Dim, FontWeights.SemiBold);
        focusBar = new Grid { ColumnSpacing = S(2) };
        startGlyph = Icon(focus.Running ? Glyphs.Pause : Glyphs.Play, 11, Theme.Background);
        startLabel = Text(focus.Running ? "Pause" : "Start", 11, Theme.Background, FontWeights.SemiBold);
        var start = Plain(Center(H(6, startGlyph, startLabel)), () => { focus.Toggle(); Right(); }, Theme.Accent, 10, new Thickness(0, S(8), 0, S(8)));
        start.HorizontalAlignment = HorizontalAlignment.Stretch;
        var presets = new ComboBox { ItemsSource = FocusPreset.All.Select(p => p.Label).ToList(), SelectedIndex = Array.IndexOf(FocusPreset.All, focus.Preset), FontSize = S(10) };
        presets.SelectionChanged += (_, _) =>
        {
            if (presets.SelectedIndex < 0) return;
            focus.Choose(FocusPreset.All[presets.SelectedIndex]);
            Model.Settings.FocusPreset = presets.SelectedIndex;
            Model.Settings.Save();
            Right();
        };
        var actions = Columns(6, (start, 1), (presets, null),
                              (IconButton(Glyphs.Refresh, () => { focus.Reset(); Right(); }, 10, Theme.Dim, "Reset"), null),
                              (IconButton(Glyphs.Next, () => { focus.Skip(); Right(); }, 10, Theme.Dim, "Skip"), null));
        var rounds = Text(focus.Rounds == 0 ? "No rounds yet today" : $"{focus.Rounds} round{(focus.Rounds == 1 ? "" : "s")} done", 8.5, Theme.Faint);
        FocusTick();
        return Rows(8, (Columns(8, (bigTime, 1), (mode, null)), null), (focusBar, null), (rounds, null), (null, 1), (actions, null));
    }

    private void FocusTick()
    {
        if (bigTime is null || focusBar is null) return;
        var focus = Model.Focus;
        bigTime.Text = Clock(focus.Left);
        const int segments = 20;
        var filled = (int)Math.Round(focus.Progress * segments);
        if (focusBar.Children.Count != segments)
        {
            focusBar.Children.Clear();
            focusBar.ColumnDefinitions.Clear();
            for (var i = 0; i < segments; i++)
            {
                focusBar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
                var seg = new Border { Height = S(8), CornerRadius = new CornerRadius(S(2)) };
                Grid.SetColumn(seg, i);
                focusBar.Children.Add(seg);
            }
        }
        var color = focus.OnBreak ? Theme.Good : Theme.Accent;
        for (var i = 0; i < segments; i++)
            ((Border)focusBar.Children[i]).Background = Theme.Brush(i < filled ? color : Theme.WithAlpha(Theme.Ink, 0.08));
    }

    private FrameworkElement TimerView()
    {
        var timer = Model.Timer;
        bigTime = Text(Clock(timer.Left), 34, weight: FontWeights.Bold, display: true);
        var chips = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = S(44), ItemHeight = S(28) };
        foreach (var m in CountdownTimer.Presets)
        {
            var on = timer.Length.TotalMinutes == m;
            chips.Children.Add(Plain(Center(Text($"{m}m", 10, on ? Theme.Background : Theme.Ink, FontWeights.SemiBold)), () => { timer.Set(m); Right(); },
                                     on ? Theme.Accent : Theme.WithAlpha(Theme.Ink, 0.07), 8, new Thickness(0, S(4), 0, S(4))));
        }
        var start = Plain(Center(H(6, Icon(timer.Running ? Glyphs.Pause : Glyphs.Play, 11, Theme.Background),
                                     Text(timer.Running ? "Pause" : "Start", 11, Theme.Background, FontWeights.SemiBold))),
                          () => { timer.Toggle(); Right(); }, Theme.Accent, 10, new Thickness(0, S(8), 0, S(8)));
        start.HorizontalAlignment = HorizontalAlignment.Stretch;
        return Rows(8, (bigTime, null), (chips, null), (null, 1), (start, null));
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
