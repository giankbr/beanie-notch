using Beanotch.Pages;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Graphics;
using static Beanotch.Ui.Ui;

namespace Beanotch.Island;

// Settings and Tools in a window of their own, as on the Mac, so the island keeps to what you glance at. One window,
// made on first use; closing it only hides it.
public sealed class SettingsWindow(Model model, Action rebuildIsland)
{
    private Window? window;
    private SettingsPage? page;

    // For the CI snapshots.
    public UIElement? View => window?.Content;

    public void Show(Tab tab)
    {
        if (window is null) Build();
        if (tab == Tab.Tools) SettingsPage.Opening = SettingsPage.Section.Tools;
        Fill();
        window!.AppWindow.Show();
        window.Activate();
    }

    private void Build()
    {
        window = new Window { Title = "Beanotch" };
        window.AppWindow.SetIcon(Path.Combine(AppContext.BaseDirectory, "Assets", "Beanotch.ico"));
        window.AppWindow.Closing += (sender, e) =>
        {
            e.Cancel = true;
            sender.Hide();
        };
        var hwnd = WinRT.Interop.WindowNative.GetWindowHandle(window);
        var scale = Native.GetDpiForWindow(hwnd) / 96.0 * K;
        window.AppWindow.Resize(new SizeInt32((int)(660 * scale), (int)(470 * scale)));
    }

    // Built again after a theme, accent or font change, since colours are baked into the elements.
    private void Fill()
    {
        if (window is null) return;
        page = new SettingsPage(model, model.Updater) { Rebuild = () => { rebuildIsland(); Fill(); } };
        window.Content = new Grid
        {
            Background = Theme.Brush(Theme.Panel),
            Padding = new Thickness(S(12)),
            RequestedTheme = Theme.Dark ? ElementTheme.Dark : ElementTheme.Light,
            Children = { page.View },
        };
        page.Refresh();
    }
}
