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
        PanelSize.Compact => (600, 300),
        PanelSize.Large => (780, 390),
        _ => (680, 336),
    };

    private readonly Model model;
    private readonly nint hwnd;
    private readonly Grid root = new();
    private readonly Border scanlines = Scanlines();
    private readonly ClosedView closed;
    private readonly Shell shell;
    private readonly DispatcherQueueTimer collapseTimer, tick, statsTimer, dataTimer;
    private Notice? notice;
    private DateTime noticeUntil;
    private (int W, int H) placed;

    public IslandWindow()
    {
        var ui = DispatcherQueue.GetForCurrentThread();
        model = new Model(ui);
        hwnd = WinRT.Interop.WindowNative.GetWindowHandle(this);
        Ui.Ui.Queue = ui;
        Pages.ShelfPage.Hwnd = hwnd;
        ApplyTheme();

        closed = new ClosedView(model);
        shell = new Shell(model, ApplyTheme);
        root.Children.Add(closed.View);
        root.Children.Add(shell.View);
        root.Children.Add(scanlines);
        shell.View.Visibility = Visibility.Collapsed;
        root.PointerEntered += (_, _) => { collapseTimer?.Stop(); Expand(); };
        root.PointerExited += (_, _) => collapseTimer?.Start();
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
        AppWindow.IsShownInSwitchers = false;
        AppWindow.Title = "Beanotch";
        AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "Beanotch.ico"));

        collapseTimer = ui.CreateTimer();
        collapseTimer.Interval = TimeSpan.FromMilliseconds(600);
        collapseTimer.IsRepeating = false;
        collapseTimer.Tick += (_, _) => Collapse();
        tick = ui.CreateTimer();
        tick.Interval = TimeSpan.FromMilliseconds(400);
        tick.Tick += (_, _) => { model.Tick(); Update(); };
        tick.Start();
        statsTimer = ui.CreateTimer();
        statsTimer.Interval = TimeSpan.FromSeconds(2);
        statsTimer.Tick += (_, _) => { if (model.Expanded) { model.Stats.Sample(); shell.Update(); } };
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
        _ = model.Updater.CheckAsync();
        dataTimer = ui.CreateTimer();
        dataTimer.Interval = TimeSpan.FromMinutes(10);
        dataTimer.Tick += (_, _) => _ = model.RefreshDataAsync();
        dataTimer.Start();
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

    private void Show(Notice n)
    {
        notice = n;
        noticeUntil = DateTime.UtcNow + n.Duration;
        Update();
    }

    private void ApplyTheme()
    {
        var systemDark = new UISettings().GetColorValue(UIColorType.Background).R < 128;
        Theme.Apply(model.Settings.Theme, model.Settings.Accent, model.Settings.Phosphor, systemDark);
        Ui.Ui.AppFont = model.Settings.Font;
        root.RequestedTheme = Theme.Dark ? ElementTheme.Dark : ElementTheme.Light;
        root.Background = Theme.Brush(model.Expanded ? Theme.Background : Theme.Black);
        ShowScanlines();
        if (model.Expanded) Place(Open.Width, Open.Height, OpenRadius, OpenEar);
    }

    // The Retro theme's CRT lines: a dark rule every third pixel over the open panel, never in the way of the pointer.
    private static Border Scanlines() => new() { IsHitTestVisible = false, Background = Ui.Ui.Scanlines() };

    private void ShowScanlines() =>
        scanlines.Visibility = model.Expanded && Theme.Retro is not null ? Visibility.Visible : Visibility.Collapsed;

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
        root.Background = Theme.Brush(Theme.Background);
        ShowScanlines();
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
        ShowScanlines();
        Update();
        FadeIn(closed.View, 3);
    }

    // Always hangs from the very top of the screen, centred, like the MacBook notch. The panel narrows on small screens
    // so it never runs off the sides.
    private void Place(double width, double height, double radius, double ear)
    {
        var scale = Native.GetDpiForWindow(hwnd) / 96.0 * Ui.Ui.K;
        var display = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary);
        width = Math.Min(width, display.WorkArea.Width / scale - 2 * ear - 24);
        int e = (int)Math.Round(ear * scale);
        int w = (int)Math.Round(width * scale) + 2 * e, h = (int)Math.Round(height * scale);
        root.Padding = new Thickness(ear * Ui.Ui.K, 0, ear * Ui.Ui.K, 0);
        if (placed == (w, h)) return;
        placed = (w, h);
        AppWindow.MoveAndResize(new RectInt32(display.OuterBounds.X + (display.OuterBounds.Width - w) / 2, display.OuterBounds.Y, w, h));
        Native.Notch(hwnd, w, h, e, (int)Math.Round(Math.Min(radius * scale, h / 2.0)));
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
