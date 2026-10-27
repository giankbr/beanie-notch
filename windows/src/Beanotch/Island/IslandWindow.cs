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

namespace Beanotch.Island;

// The island: a black pill at the top centre of the screen that grows into the panel on hover, standing in for the
// Mac's notch. Files dropped on it go to the Shelf.
public sealed partial class IslandWindow : Window
{
    // Mac points; scaled by Ui.K and then by the monitor's DPI.
    private const double ClosedHeight = 30, OpenWidth = 680, OpenHeight = 336, TopGap = 6, OpenRadius = 22;

    private readonly Model model;
    private readonly nint hwnd;
    private readonly Grid root = new();
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
        Theme.Apply(model.Settings.Theme, model.Settings.Accent, systemDark);
        root.RequestedTheme = Theme.Dark ? ElementTheme.Dark : ElementTheme.Light;
        root.Background = Theme.Brush(model.Expanded ? Theme.Background : Theme.Black);
    }

    private void Update()
    {
        if (notice is not null && DateTime.UtcNow > noticeUntil) notice = null;
        if (model.Expanded) shell.Tick();
        else
        {
            var width = closed.Update(notice);
            Place(width, ClosedHeight, ClosedHeight / 2);
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
        shell.Shown();
        Place(OpenWidth, OpenHeight, OpenRadius);
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
    }

    // Centred at the top of the work area on the island's screen.
    private void Place(double width, double height, double radius)
    {
        var scale = Native.GetDpiForWindow(hwnd) / 96.0 * Ui.Ui.K;
        int w = (int)Math.Round(width * scale), h = (int)Math.Round(height * scale);
        if (placed == (w, h)) return;
        placed = (w, h);
        var area = DisplayArea.GetFromWindowId(AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        AppWindow.MoveAndResize(new RectInt32(area.X + (area.Width - w) / 2, area.Y + (int)(TopGap * scale), w, h));
        Native.Round(hwnd, w, h, (int)Math.Round(radius * scale));
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
