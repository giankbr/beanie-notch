using System.Globalization;
using Beanotch.Core;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;

namespace Beanotch;

public sealed partial class MainWindow : Window
{
    // In device-independent pixels; scaled by the monitor's DPI when placed.
    private const int ClosedWidth = 260, ClosedHeight = 36, OpenWidth = 720, OpenHeight = 340, TopGap = 8;

    private readonly nint hwnd;
    private readonly AppSettings settings = AppSettings.Load();
    private readonly MediaWatcher media;
    private readonly ClipboardWatcher clipboard = new();
    private readonly DispatcherQueueTimer collapseTimer;
    private readonly DispatcherQueueTimer tick;
    private bool expanded;
    private string tab = "music";
    private DateOnly prayerDay;

    public MainWindow()
    {
        InitializeComponent();
        hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);

        var presenter = OverlappedPresenter.Create();
        presenter.IsAlwaysOnTop = true;
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        presenter.SetBorderAndTitleBar(false, false);
        AppWindow.SetPresenter(presenter);
        AppWindow.IsShownInSwitchers = false;
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "Beanotch.ico"));
        Native.RoundCorners(hwnd);
        Place(ClosedWidth, ClosedHeight);

        var queue = DispatcherQueue.GetForCurrentThread();
        collapseTimer = queue.CreateTimer();
        collapseTimer.Interval = TimeSpan.FromMilliseconds(600);
        collapseTimer.IsRepeating = false;
        collapseTimer.Tick += (_, _) => Collapse();
        tick = queue.CreateTimer();
        tick.Interval = TimeSpan.FromMilliseconds(500);
        tick.Tick += (_, _) => Update();
        tick.Start();

        media = new MediaWatcher(queue);
        media.Changed += Update;
        _ = media.StartAsync();

        ClipList.ItemsSource = clipboard.Items;
        clipboard.Items.CollectionChanged += (_, _) => ClipboardEmpty.Visibility = clipboard.Items.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

        CityPicker.ItemsSource = PrayerTimes.Cities.Select(c => c.Name).ToList();
        CityPicker.SelectedItem = settings.Place.Name;
        MethodPicker.ItemsSource = Enum.GetValues<PrayerMethod>().Select(PrayerTimes.Title).ToList();
        MethodPicker.SelectedIndex = (int)settings.Method;
        RefreshPrayers();
        Update();
    }

    // Centred at the top of the work area on the island's screen: Windows has no notch to sit around.
    private void Place(int width, int height)
    {
        var scale = Native.GetDpiForWindow(hwnd) / 96.0;
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        int w = (int)(width * scale), h = (int)(height * scale);
        AppWindow.MoveAndResize(new RectInt32(area.X + (area.Width - w) / 2, area.Y + (int)(TopGap * scale), w, h));
    }

    private void OnPointerEntered(object sender, PointerRoutedEventArgs e)
    {
        collapseTimer.Stop();
        if (expanded) return;
        expanded = true;
        Closed.Visibility = Visibility.Collapsed;
        Open.Visibility = Visibility.Visible;
        Root.Background = new SolidColorBrush(Microsoft.UI.ColorHelper.FromArgb(255, 0x13, 0x13, 0x15));
        Place(OpenWidth, OpenHeight);
        if (tab == "ai") RefreshAi();
    }

    private void OnPointerExited(object sender, PointerRoutedEventArgs e) => collapseTimer.Start();

    private void Collapse()
    {
        // An open drop-down (the city picker) lives outside the window's bounds; wait until it closes.
        if (Content.XamlRoot is not null && VisualTreeHelper.GetOpenPopupsForXamlRoot(Content.XamlRoot).Count > 0)
        {
            collapseTimer.Start();
            return;
        }
        expanded = false;
        Open.Visibility = Visibility.Collapsed;
        Closed.Visibility = Visibility.Visible;
        Root.Background = new SolidColorBrush(Microsoft.UI.ColorHelper.FromArgb(255, 0x0B, 0x0B, 0x0C));
        Place(ClosedWidth, ClosedHeight);
    }

    private void OnTabChanged(SelectorBar sender, SelectorBarSelectionChangedEventArgs args)
    {
        tab = sender.SelectedItem?.Tag as string ?? "music";
        // The first selection fires while the XAML is still loading, before the pages exist.
        if (AiPage is null) return;
        MusicPage.Visibility = tab == "music" ? Visibility.Visible : Visibility.Collapsed;
        ClipboardPage.Visibility = tab == "clipboard" ? Visibility.Visible : Visibility.Collapsed;
        PrayerPage.Visibility = tab == "prayer" ? Visibility.Visible : Visibility.Collapsed;
        AiPage.Visibility = tab == "ai" ? Visibility.Visible : Visibility.Collapsed;
        if (tab == "ai") RefreshAi();
    }

    private void Update()
    {
        var line = media.CurrentLine;
        var next = PrayerTimes.Next(DateTimeOffset.Now, DateOnly.FromDateTime(DateTime.Now), settings.Place, settings.Method);
        var untilPrayer = next.Time - DateTimeOffset.Now;

        // Closed: a lyric line while music plays, the track otherwise, and the next prayer when nothing plays.
        if (media.Playing && media.HasTrack)
        {
            ClosedIcon.Glyph = "";
            ClosedText.Text = string.IsNullOrEmpty(line?.Text) ? media.Title : line.Text;
            ClosedTrail.Text = "";
        }
        else
        {
            ClosedIcon.Glyph = "";
            ClosedText.Text = next.Name;
            ClosedTrail.Text = Countdown(untilPrayer);
        }

        if (expanded && tab == "music") UpdateMusic(line);
        if (expanded && tab == "prayer")
        {
            NextPrayer.Text = $"{next.Name} {next.Time.ToLocalTime():HH.mm}";
            NextCountdown.Text = $"in {Countdown(untilPrayer)} · {PrayerTimes.Title(settings.Method)}";
        }
        if (DateOnly.FromDateTime(DateTime.Now) != prayerDay) RefreshPrayers();
    }

    private void UpdateMusic(LyricLine? line)
    {
        TrackTitle.Text = media.HasTrack ? media.Title : "Nothing playing";
        TrackArtist.Text = media.Artist;
        Artwork.Source = media.Art;
        PlayGlyph.Glyph = media.Playing ? "" : "";
        var duration = media.Duration;
        var position = media.Position;
        Progress.Value = duration > TimeSpan.Zero ? position / duration : 0;
        Elapsed.Text = Clock(position);
        Remaining.Text = duration > TimeSpan.Zero ? "-" + Clock(duration - position) : "";

        var lines = media.Lines;
        var index = line is null ? -1 : IndexOf(lines, line);
        LyricBefore.Text = index > 0 ? lines[index - 1].Text : "";
        LyricNow.Text = index >= 0 ? line!.Text : media.HasTrack && lines.Count == 0 ? "No synced lyrics for this song" : "";
        LyricAfter.Text = index >= 0 && index + 1 < lines.Count ? lines[index + 1].Text : "";
    }

    private static int IndexOf(IReadOnlyList<LyricLine> lines, LyricLine line)
    {
        for (var i = 0; i < lines.Count; i++) if (ReferenceEquals(lines[i], line)) return i;
        return -1;
    }

    private void RefreshPrayers()
    {
        prayerDay = DateOnly.FromDateTime(DateTime.Now);
        var entries = PrayerTimes.Compute(prayerDay, settings.Place, settings.Method);
        var next = PrayerTimes.Next(DateTimeOffset.Now, prayerDay, settings.Place, settings.Method);
        PrayerList.ItemsSource = entries.Select(e => new PrayerRow(e.Name, e.Time.ToLocalTime().ToString("HH.mm", CultureInfo.InvariantCulture),
            e.Time < DateTimeOffset.Now ? 0.45 : 1, e.Time == next.Time)).ToList();
    }

    private void RefreshAi()
    {
        AiCost.Text = "…";
        _ = Task.Run(() => ClaudeUsage.Read(ClaudeUsage.DefaultRoot, DateTimeOffset.Now)).ContinueWith(task =>
        {
            var usage = task.Result;
            DispatcherQueue.TryEnqueue(() =>
            {
                AiCost.Text = usage.CostToday.ToString("$0.00", CultureInfo.InvariantCulture);
                AiTokens.Text = $"{Tokens(usage.TokensToday)} tokens · {usage.RequestsToday} requests";
                AiWeek.Text = $"{usage.CostWeek.ToString("$0", CultureInfo.InvariantCulture)} this week";
                ModelList.ItemsSource = usage.ModelsToday.Select(m => new ModelRow(m.Model, Tokens(m.Tokens),
                    m.Cost.ToString("$0.00", CultureInfo.InvariantCulture))).ToList();
            });
        }, TaskScheduler.Default);
    }

    private void OnCityChanged(object sender, SelectionChangedEventArgs e)
    {
        if (CityPicker.SelectedItem is not string city || city == settings.City) return;
        settings.City = city;
        settings.Save();
        RefreshPrayers();
        Update();
    }

    private void OnMethodChanged(object sender, SelectionChangedEventArgs e)
    {
        if (MethodPicker.SelectedIndex < 0 || (PrayerMethod)MethodPicker.SelectedIndex == settings.Method) return;
        settings.Method = (PrayerMethod)MethodPicker.SelectedIndex;
        settings.Save();
        RefreshPrayers();
        Update();
    }

    private void OnClipClick(object sender, ItemClickEventArgs e)
    {
        if (e.ClickedItem is ClipItem item) clipboard.Copy(item);
    }

    private void OnPlayPause(object sender, RoutedEventArgs e) => media.TogglePlay();
    private void OnNext(object sender, RoutedEventArgs e) => media.Next();
    private void OnPrevious(object sender, RoutedEventArgs e) => media.Previous();
    private void OnQuit(object sender, RoutedEventArgs e) => Application.Current.Exit();

    private static string Countdown(TimeSpan span) =>
        span.TotalMinutes < 60 ? $"{Math.Max(1, (int)Math.Ceiling(span.TotalMinutes))} min" : $"{(int)span.TotalHours}h {span.Minutes}m";

    private static string Clock(TimeSpan span) => span.TotalHours >= 1 ? span.ToString(@"h\:mm\:ss") : span.ToString(@"m\:ss");

    private static string Tokens(long count) => count switch
    {
        >= 1_000_000_000 => (count / 1e9).ToString("0.0", CultureInfo.InvariantCulture) + "B",
        >= 1_000_000 => (count / 1e6).ToString("0.0", CultureInfo.InvariantCulture) + "M",
        >= 1_000 => (count / 1e3).ToString("0", CultureInfo.InvariantCulture) + "K",
        _ => count.ToString(CultureInfo.InvariantCulture),
    };
}
