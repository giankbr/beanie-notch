using System.Runtime.InteropServices.WindowsRuntime;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;

namespace Beanotch.Island;

// With BEANOTCH_SNAPSHOT=<folder>, the app photographs the closed island, a notice, every page in the dark theme and
// a few in the light one, then quits. CI runs this on a Windows machine so the UI can be looked at without a PC.
public sealed partial class IslandWindow
{
    public static string? SnapshotFolder => Environment.GetEnvironmentVariable("BEANOTCH_SNAPSHOT") is { Length: > 0 } dir ? dir : null;

    private async Task SnapshotAsync(string dir)
    {
        Directory.CreateDirectory(dir);
        var log = new List<string>();
        async Task Shot(string name, int wait = 1500)
        {
            await Task.Delay(wait);
            try
            {
                await Save(root, Path.Combine(dir, name + ".png"));
                log.Add($"ok   {name}");
            }
            catch (Exception e) { log.Add($"FAIL {name}: {e.GetType().Name}: {e.Message}"); }
        }

        await Shot("01-closed-idle", 3000);
        Show(new Notice(Glyphs.Volume, Theme.Accent, "Volume", "64", TimeSpan.FromSeconds(10), 0.64, "volume"));
        await Shot("02-closed-volume");
        Show(new Notice(Glyphs.Mic, Theme.Red, "Mic in use", "Zoom", TimeSpan.FromSeconds(10), Key: "microphone"));
        await Shot("03-closed-mic");
        notice = null;
        model.Settings.NotchPet = true;
        Update();
        await Shot("03b-closed-pet");
        Show(new Notice(Glyphs.Screenshot, Theme.Accent2, "Screenshot", "On the Shelf", TimeSpan.FromSeconds(10)));
        await Shot("03c-closed-pet-notice", 600);
        notice = null;
        foreach (var kind in new[] { PetKind.Cat, PetKind.Frog, PetKind.Ghost })
        {
            model.Settings.PetKind = kind;
            Update();
            await Shot($"03d-closed-pet-{kind.ToString().ToLowerInvariant()}", 700);
        }
        model.Settings.PetKind = PetKind.Bean;
        model.Settings.NotchPet = false;
        Update();

        Expand();
        var index = 4;
        foreach (var tab in Enum.GetValues<Tab>())
        {
            try { shell.Open(tab); }
            catch (Exception e) { log.Add($"FAIL open {tab}: {e.GetType().Name}: {e.Message}"); continue; }
            await Shot($"{index++:00}-dark-{tab.ToString().ToLowerInvariant()}", tab is Tab.Ai or Tab.Tools or Tab.Controls ? 4000 : 2000);
        }

        model.Focus.Toggle();
        shell.Open(Tab.Today);
        await Shot($"{index++:00}-dark-focus-running", 2500);
        model.Focus.Skip();
        shell.Open(Tab.Home);
        shell.Open(Tab.Today);
        await Shot($"{index++:00}-dark-focus-break");
        model.Focus.Reset();

        model.Settings.Theme = ThemeMode.Light;
        model.Settings.Accent = AccentChoice.Ocean;
        shell.Rebuild();
        root.Background = Theme.Brush(Theme.Panel);
        foreach (var tab in new[] { Tab.Home, Tab.Today, Tab.Prayer, Tab.Settings })
        {
            shell.Open(tab);
            await Shot($"{index++:00}-light-{tab.ToString().ToLowerInvariant()}");
        }

        model.Settings.Theme = ThemeMode.Dark;
        foreach (var font in new[] { AppFont.BeVietnam, AppFont.Inter, AppFont.Jakarta })
        {
            model.Settings.Font = font;
            shell.Rebuild();
            root.Background = Theme.Brush(Theme.Panel);
            shell.Open(Tab.Home);
            await Shot($"{index++:00}-font-{font.ToString().ToLowerInvariant()}");
        }

        model.Settings.Font = AppFont.System;
        foreach (var size in new[] { PanelSize.Compact, PanelSize.Large })
        {
            model.Settings.Size = size;
            shell.Rebuild();
            shell.Open(Tab.Home);
            await Shot($"{index++:00}-size-{size.ToString().ToLowerInvariant()}");
        }
        model.Settings.Size = PanelSize.Regular;
        Pages.TodayPage.StartLeft = 3;
        shell.Rebuild();
        shell.Open(Tab.Today);
        await Shot($"{index++:00}-today-rates", 6000);
        Pages.TodayPage.StartLeft = 0;
        foreach (var (theme, tab) in new[] { (ThemeMode.Midnight, Tab.Home), (ThemeMode.Midnight, Tab.Today), (ThemeMode.Glass, Tab.Home), (ThemeMode.Glass, Tab.Settings), (ThemeMode.Keycap, Tab.Home), (ThemeMode.Keycap, Tab.Settings), (ThemeMode.Pixel, Tab.Home), (ThemeMode.Pixel, Tab.Today) })
        {
            model.Settings.Theme = theme;
            ApplyTheme();
            shell.Rebuild();
            shell.Open(tab);
            // The acrylic only shows on screen, not in these renders: tell CI to photograph the desktop now.
            if (theme == ThemeMode.Glass && tab == Tab.Home) File.WriteAllText(Path.Combine(dir, "glass.ready"), "");
            await Shot($"{index++:00}-{theme.ToString().ToLowerInvariant()}-{tab.ToString().ToLowerInvariant()}", theme == ThemeMode.Glass ? 5000 : 1500);
        }

        // The ruler: the photographed screen with its crosshairs, rendered, then photographed on screen by CI.
        try
        {
            RulerWindow.ShowRuler();
            await Task.Delay(2500);
            if (RulerWindow.Showing?.Content is UIElement ruler) await Save(ruler, Path.Combine(dir, $"{index++:00}-ruler.png"));
            File.WriteAllText(Path.Combine(dir, "ruler.ready"), "");
            await Task.Delay(5000);
            RulerWindow.Showing?.Close();
            log.Add("ok   ruler");
        }
        catch (Exception e) { log.Add($"FAIL ruler: {e.GetType().Name}: {e.Message}"); }

        File.WriteAllLines(Path.Combine(dir, "snapshot.log"), log);
        Microsoft.UI.Xaml.Application.Current.Exit();
    }

    private static async Task Save(UIElement element, string path)
    {
        var bitmap = new RenderTargetBitmap();
        await bitmap.RenderAsync(element);
        var pixels = await bitmap.GetPixelsAsync();
        await using var file = File.Create(path);
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, file.AsRandomAccessStream());
        encoder.SetPixelData(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Premultiplied, (uint)bitmap.PixelWidth, (uint)bitmap.PixelHeight, 96, 96, pixels.ToArray());
        await encoder.FlushAsync();
    }
}
