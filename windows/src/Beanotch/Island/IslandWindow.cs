using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using Windows.Graphics;
using Windows.Storage;
using Windows.UI.ViewManagement;
using static Beanotch.Ui.Ui;

namespace Beanotch.Island;

// The island: a black pill at the top centre of the screen that grows into the panel on hover, standing in for the
// Mac's notch. Files dropped on it go to the Shelf.
public sealed partial class IslandWindow : Window
{
    // Mac points; scaled by Ui.K and then by the monitor's DPI.
    // Mac points, as in the Mac app: the closed notch, the open panel, and the shoulders where the notch meets the top
    // edge of the screen.
    private const double ClosedHeight = 30, ClosedRadius = 10, ClosedEar = 6, OpenRadius = 22, OpenEar = 14;

    // The open panel at each size, a little taller than the Mac's since Windows sets text larger.
    private (double Width, double Height) Open => model.Settings.Size switch
    {
        PanelSize.Compact => (630, 300),
        PanelSize.Large => (780, 390),
        _ => (680, 336),
    };

    private readonly Model model;
    private readonly nint hwnd;
    private readonly Grid root = new();
    private readonly ClosedView closed;
    private readonly Shell shell;
    private readonly DispatcherQueueTimer collapseTimer, tick, statsTimer, dataTimer, quakeTimer, updateTimer;
    // A notice's link that installs the update instead of opening a page.
    private static readonly Uri InstallUpdate = new("beanotch:update");
    private Notice? notice;
    // Alerts that can wait, held while a call is on.
    private readonly List<Notice> held = [];
    private DateTime noticeUntil;
    private (int W, int H, NotchShape Shape) placed;
    private bool hiddenForFullscreen;
    // Opened from the keyboard: stays open until the shortcut again, Esc, or the pointer comes and goes.
    private bool pinnedOpen;

    public string? Hotkey { get; private set; }

    public void HotkeyChanged() => Hotkey = model.Settings.Hotkey ? Native.RegisterToggleHotkey(hwnd) : Native.UnregisterToggleHotkey(hwnd);

    // For Settings, which has no window of its own: re-register the shortcut, and say which one took.
    public static Action? ApplyHotkey;
    public static Func<string?>? CurrentHotkey;
    private int fullscreenVotes;
    private readonly DispatcherQueueTimer petStroke;

    private bool OnPet(Microsoft.UI.Xaml.Input.PointerRoutedEventArgs e)
    {
        if (model.Expanded || !model.Settings.NotchPet) return false;
        var spot = closed.PetSpot;
        var p = e.GetCurrentPoint(spot).Position;
        return p.X >= -4 && p.Y >= -4 && p.X <= spot.ActualWidth + 4 && p.Y <= spot.ActualHeight + 4;
    }

    // Out of the way while a game, a video or a slideshow fills the screen, and back when it doesn't.
    private void HideForFullscreen()
    {
        var hide = model.Settings.HideInFullscreen && !model.Expanded && Native.FullscreenAppOpen(hwnd);
        // A change has to hold for a few ticks (over a second) before the island follows it, so a window passing
        // through full screen size, or a moment's focus change, doesn't make it blink.
        fullscreenVotes = hide == hiddenForFullscreen ? 0 : fullscreenVotes + 1;
        if (fullscreenVotes < 3) return;
        fullscreenVotes = 0;
        hiddenForFullscreen = hide;
        if (hide) AppWindow.Hide();
        else AppWindow.Show(false);
    }

    public IslandWindow()
    {
        var ui = DispatcherQueue.GetForCurrentThread();
        model = new Model(ui);
        hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        Ui.Ui.Queue = ui;
        Pages.ShelfPage.Hwnd = hwnd;
        ApplyTheme();

        closed = new ClosedView(model, PetAnchor);
        shell = new Shell(model, ApplyTheme);
        root.Children.Add(closed.View);
        root.Children.Add(shell.View);
        shell.View.Visibility = Visibility.Collapsed;
        // A notice with a link waits for its click instead of opening the panel on hover. The pet's corner doesn't
        // open it either: there the pointer pets it, a click taps it and a scroll sways it.
        petStroke = ui.CreateTimer();
        petStroke.Interval = TimeSpan.FromSeconds(1.2);
        petStroke.IsRepeating = false;
        petStroke.Tick += (_, _) => model.Pet.Stroke();
        root.PointerEntered += (_, e) =>
        {
            collapseTimer?.Stop();
            pinnedOpen = false;
            if (OnPet(e)) { petStroke.Start(); return; }
            if (model.Expanded || notice?.Open is null && model.Settings.OpenOnHover) Expand();
        };
        root.PointerMoved += (_, e) =>
        {
            if (model.Expanded) return;
            if (OnPet(e)) { if (!petStroke.IsRunning) petStroke.Start(); return; }
            petStroke.Stop();
            if (notice?.Open is null && model.Settings.OpenOnHover) Expand();
        };
        root.PointerWheelChanged += (_, e) =>
        {
            if (OnPet(e)) { model.Pet.Sway(); return; }
            // Over the closed island, a scroll sets the volume, as over the Mac's notch.
            if (model.Expanded || !model.Settings.ScrollVolume || Audio.Speaker() is not { } speaker) return;
            var delta = e.GetCurrentPoint(root).Properties.MouseWheelDelta;
            Audio.SetSpeaker(Math.Clamp(speaker.Level + Math.Sign(delta) * 0.04, 0, 1));
            e.Handled = true;
        };
        root.PointerPressed += (_, e) =>
        {
            if (model.Expanded) return;
            if (OnPet(e)) { model.Pet.Tap(); return; }
            if (notice?.Open == InstallUpdate) _ = model.Updater.InstallAsync();
            else if (notice?.Open is { } link) _ = Windows.System.Launcher.LaunchUriAsync(link);
            else Expand();
        };
        root.PointerExited += (_, _) =>
        {
            petStroke.Stop();
            if (collapseTimer is null || pinnedOpen) return;
            collapseTimer.Interval = TimeSpan.FromSeconds(Math.Clamp(model.Settings.CloseDelay, 0.2, 5));
            collapseTimer.Start();
        };
        root.AllowDrop = true;
        root.DragOver += OnDragOver;
        root.Drop += OnDrop;
        Content = root;

        var presenter = OverlappedPresenter.Create();
        presenter.IsAlwaysOnTop = true;
        presenter.IsResizable = false;
        presenter.IsMaximizable = false;
        presenter.IsMinimizable = false;
        presenter.SetBorderAndTitleBar(false, false);
        AppWindow.SetPresenter(presenter);
        Native.Frameless(hwnd);
        // Alt+Space opens and closes the panel from anywhere, as ⌥ Space does on the Mac (Ctrl+Alt+Space if another
        // app, PowerToys Run say, already has it).
        Native.HotkeyPressed = () => ui.TryEnqueue(() => { if (model.Expanded) Collapse(); else { Expand(); pinnedOpen = true; } });
        HotkeyChanged();
        ApplyHotkey = HotkeyChanged;
        CurrentHotkey = () => Hotkey;
        AppWindow.IsShownInSwitchers = false;
        AppWindow.Title = "Beanotch";
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "Beanotch.ico"));

        collapseTimer = ui.CreateTimer();
        collapseTimer.Interval = TimeSpan.FromMilliseconds(600);
        collapseTimer.IsRepeating = false;
        collapseTimer.Tick += (_, _) => Collapse();
        tick = ui.CreateTimer();
        tick.Interval = TimeSpan.FromMilliseconds(400);
        tick.Tick += (_, _) =>
        {
            model.Tick();
            model.Pet.Tick(notice is null && !model.Expanded && model.Watchers.CallSince is null && !model.Focus.Running && !model.Media.Playing);
            Update();
            HideForFullscreen();
        };
        model.Pet.LeveledUp += level =>
        {
            var unlocked = Enum.GetValues<PetAccessory>().FirstOrDefault(a => a != PetAccessory.None && Pet.LevelFor(a) == level);
            Show(new Notice("\uE734", Theme.Amber, $"{model.Pet.Name} reached level {level}",
                            unlocked == PetAccessory.None ? "Good company" : $"Unlocked: {unlocked}", TimeSpan.FromSeconds(6)));
        };

        tick.Start();
        statsTimer = ui.CreateTimer();
        statsTimer.Interval = TimeSpan.FromSeconds(2);
        statsTimer.Tick += (_, _) =>
        {
            if (model.Expanded) { model.Stats.Sample(); shell.Update(); }
            // The pet sweats when the processor is busy, so it needs the reading while the island is closed too.
            else if (model.Settings.NotchPet) model.Stats.Sample();
        };
        statsTimer.Start();

        model.Media.Changed += Update;
        model.Watchers.Notice += Show;
        model.Notice += Show;
        model.Cleaner.Changed += () => shell.Update();
        _ = model.Media.StartAsync();
        model.Watchers.Start();
        model.Stats.Sample();
        _ = model.Cleaner.ScanAsync();
        _ = model.RefreshDataAsync();
        // A new release is looked for at start and every six hours, and announced once per version.
        updateTimer = ui.CreateTimer();
        updateTimer.Interval = TimeSpan.FromHours(6);
        updateTimer.Tick += (_, _) => _ = CheckForUpdate();
        updateTimer.Start();
        _ = CheckForUpdate();
        dataTimer = ui.CreateTimer();
        dataTimer.Interval = TimeSpan.FromMinutes(10);
        dataTimer.Tick += (_, _) => _ = model.RefreshDataAsync();
        dataTimer.Start();
        quakeTimer = ui.CreateTimer();
        quakeTimer.Interval = TimeSpan.FromMinutes(1);
        quakeTimer.Tick += (_, _) => _ = model.Quakes.CheckAsync();
        quakeTimer.Start();
        RulerWindow.Measured = size => Show(new Notice("\uED5E", Theme.Accent, "Copied", size, TimeSpan.FromSeconds(4), Essential: true));
        _ = model.Quakes.CheckAsync();
        model.Watchers.CallEnded += length =>
        {
            var waiting = held.ToList();
            held.Clear();
            Show(new Notice(Glyphs.Mic, Theme.Accent, "Call ended · " + DevRuns.Duration(length),
                            waiting.Count == 0 ? "Nothing missed" : waiting.Count == 1 ? "1 alert held" : $"{waiting.Count} alerts held",
                            TimeSpan.FromSeconds(4), Essential: true));
            // Then the last few that waited, one after another.
            foreach (var (n, i) in waiting.TakeLast(3).Select((n, i) => (n, i)))
            {
                var later = ui.CreateTimer();
                later.Interval = TimeSpan.FromSeconds(4.5 * (i + 1));
                later.IsRepeating = false;
                later.Tick += (_, _) => Show(n);
                later.Start();
            }
        };
        Update();

        if (SnapshotFolder is { } dir)
        {
            var started = false;
            Activated += (_, _) =>
            {
                if (started) return;
                started = true;
                _ = SnapshotAsync(dir);
            };
        }
    }

    // The pet's eyes, in screen pixels: near the island's right end, a little below the top edge.
    private (Windows.Foundation.Point, double)? PetAnchor()
    {
        if (model.Expanded) return null;
        var scale = Native.GetDpiForWindow(hwnd) / 96.0 * Ui.Ui.K;
        var at = AppWindow.Position;
        return (new Windows.Foundation.Point(at.X + 34 * scale, at.Y + 15 * scale), scale);
    }

    private async Task CheckForUpdate()
    {
        await model.Updater.CheckAsync();
        if (!model.Updater.UpdateAvailable || model.Updater.Latest is not { } latest || model.Settings.AnnouncedVersion == latest) return;
        model.Settings.AnnouncedVersion = latest;
        model.Settings.Save();
        Show(new Notice(Glyphs.Download, Theme.Accent2, $"Beanotch {latest}", "Click to update", TimeSpan.FromSeconds(15),
                        Essential: true, Open: InstallUpdate));
    }

    private void Show(Notice n)
    {
        if (model.Watchers.CallSince is not null && !n.Essential && n.Key is not ("volume" or "caps" or "microphone" or "webcam"))
        {
            held.Add(n);
            return;
        }
        notice = n;
        noticeUntil = DateTime.UtcNow + n.Duration;
        if (model.Settings.NotchPet) model.Pet.React(n);
        Update();
    }

    private void ApplyTheme()
    {
        var systemDark = new UISettings().GetColorValue(UIColorType.Background).R < 128;
        Theme.Apply(model.Settings.Theme, model.Settings.Accent, systemDark);
        Ui.Ui.AppFont = model.Settings.Font;
        root.RequestedTheme = Theme.Dark ? ElementTheme.Dark : ElementTheme.Light;
        // Glass: the desktop behind the window, blurred, under the panel's dark wash.
        SystemBackdrop = Theme.Mode == ThemeMode.Glass ? new DesktopAcrylicBackdrop() : null;
        root.Background = Theme.Brush(model.Expanded ? Theme.Panel : Theme.Black);
        if (model.Expanded) Place(Open.Width, Open.Height, OpenRadius, OpenEar);
    }

    private void Update()
    {
        if (notice is not null && DateTime.UtcNow > noticeUntil) notice = null;
        if (model.Expanded) shell.Tick();
        else
        {
            var width = closed.Update(notice);
            Place(width, ClosedHeight, ClosedRadius, ClosedEar);
        }
    }

    private void Expand()
    {
        if (model.Expanded) return;
        model.Expanded = true;
        model.Stats.Sample();
        closed.View.Visibility = Visibility.Collapsed;
        shell.View.Visibility = Visibility.Visible;
        root.Background = Theme.Brush(Theme.Panel);
        shell.Shown();
        Place(Open.Width, Open.Height, OpenRadius, OpenEar);
        FadeIn(shell.View);
    }

    private void Collapse()
    {
        // An open drop-down or menu lives outside the window; wait until it closes.
        if (root.XamlRoot is not null && VisualTreeHelper.GetOpenPopupsForXamlRoot(root.XamlRoot).Count > 0)
        {
            collapseTimer.Start();
            return;
        }
        model.Expanded = false;
        shell.View.Visibility = Visibility.Collapsed;
        closed.View.Visibility = Visibility.Visible;
        root.Background = Theme.Brush(Theme.Black);
        Update();
        FadeIn(closed.View, 3);
    }

    // Hangs from the very top of the screen, centred, like the MacBook notch (or just below it, floating). The panel
    // narrows on small screens so it never runs off the sides.
    private void Place(double width, double height, double radius, double ear)
    {
        var shape = model.Settings.Shape;
        if (shape != NotchShape.Drop) ear = 0;
        var scale = Native.GetDpiForWindow(hwnd) / 96.0 * Ui.Ui.K;
        var display = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        width = Math.Min(width, display.WorkArea.Width / scale - 2 * ear - 24);
        int e = (int)Math.Round(ear * scale);
        int w = (int)Math.Round(width * scale) + 2 * e, h = (int)Math.Round(height * scale);
        root.Padding = new Thickness(ear * Ui.Ui.K, 0, ear * Ui.Ui.K, 0);
        if (placed == (w, h, shape)) return;
        placed = (w, h, shape);
        var drop = shape == NotchShape.Floating ? (int)Math.Round(8 * scale) : 0;
        AppWindow.MoveAndResize(new RectInt32(display.OuterBounds.X + (display.OuterBounds.Width - w) / 2, display.OuterBounds.Y + drop, w, h));
        Native.Notch(hwnd, w, h, e, (int)Math.Round(Math.Min(radius * scale, h / 2.0)), shape == NotchShape.Floating);
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;
        e.AcceptedOperation = DataPackageOperation.Copy;
        e.DragUIOverride.Caption = "Keep on the Shelf";
        if (!model.Expanded)
        {
            Expand();
            shell.Open(Tab.Shelf);
        }
    }

    private async void OnDrop(object sender, DragEventArgs e)
    {
        if (!e.DataView.Contains(StandardDataFormats.StorageItems)) return;
        var deferral = e.GetDeferral();
        try
        {
            var items = await e.DataView.GetStorageItemsAsync();
            model.Shelf.Add(items.OfType<IStorageItem>().Select(i => i.Path).Where(p => !string.IsNullOrEmpty(p)));
            shell.Open(Tab.Shelf);
        }
        catch (Exception) { }
        finally { deferral.Complete(); }
    }
}
