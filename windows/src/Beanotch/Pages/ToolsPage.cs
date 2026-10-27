using System.Diagnostics;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage;
using Windows.Storage.FileProperties;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Tools: an uninstaller that also finds what an app leaves behind, a large-file finder, and the camera.
public sealed class ToolsPage(Model model) : PanelPage(model)
{
    private readonly Grid head = new();
    private readonly Grid body = new();
    private StackPanel bar = H(6);
    private int mode;
    private List<InstalledApp>? apps;
    private InstalledApp? selected;
    private List<(string Path, long Size)>? leftovers;
    private List<LargeFile>? large;
    private bool scanning;
    private string query = "";

    protected override FrameworkElement Build() => Rows(8, (head, null), (body, 1));

    public override void Refresh()
    {
        // The header is rebuilt with a fresh bar each time: an element can only sit in one parent.
        bar = H(6);
        head.Children.Clear();
        head.Children.Add(Columns(8, (Segmented(["Uninstaller", "Large files", "Mirror"], mode, i => { mode = i; Refresh(); }), 1), (bar, null),
                                  (PillButton("Ruler", Theme.Accent, Island.RulerWindow.ShowRuler, "\uED5E"), null)));
        body.Children.Clear();
        if (mode == 0) Apps();
        else if (mode == 1) Large();
        else Mirror();
    }

    private void Apps()
    {
        bar.Children.Add(PillButton("Refresh", Theme.Accent2, () => { apps = null; Refresh(); }, Glyphs.Refresh));
        if (apps is null)
        {
            body.Children.Add(Text("Reading installed apps…", 10.5, Theme.Faint));
            _ = Task.Run(Uninstaller.Read).ContinueWith(t => Dispatch(() => { apps = t.IsCompletedSuccessfully ? t.Result : []; Refresh(); }), TaskScheduler.Default);
            return;
        }
        var search = new TextBox { PlaceholderText = "Search apps", Text = query, FontSize = S(10.5) };
        var list = V(2);
        void Fill()
        {
            list.Children.Clear();
            foreach (var app in apps.Where(a => query.Length == 0 || a.Name.Contains(query, StringComparison.OrdinalIgnoreCase)).Take(60))
            {
                var icon = new Image { Width = S(18), Height = S(18) };
                if (app.Icon is { } path) _ = Thumb(path, icon);
                var row = Columns(10, (icon, null), (Text(app.Name, 10.5, weight: app == selected ? FontWeights.SemiBold : FontWeights.Normal), 1));
                row.Padding = new Thickness(S(8), S(5), S(8), S(5));
                var b = Plain(row, () => Select(app), app == selected ? Theme.WithAlpha(Theme.Accent, 0.14) : Ui.Ui.Transparent, 8);
                b.HorizontalAlignment = HorizontalAlignment.Stretch;
                list.Children.Add(b);
            }
        }
        search.TextChanged += (_, _) => { query = search.Text.Trim(); Fill(); };
        Fill();
        var left = Rows(6, (search, null), (Scroll(list), 1));
        left.Width = S(250);
        body.Children.Add(Columns(10, (left, null), (Detail(), 1)));
    }

    private void Select(InstalledApp app)
    {
        selected = app;
        leftovers = null;
        Refresh();
        _ = Task.Run(() => Uninstaller.Leftovers(app)).ContinueWith(t => Dispatch(() =>
        {
            if (selected != app) return;
            leftovers = t.IsCompletedSuccessfully ? t.Result : [];
            Refresh();
        }), TaskScheduler.Default);
    }

    private FrameworkElement Detail()
    {
        if (selected is null)
            return Card(Center(Text("Pick an app to see what it leaves behind", 10.5, Theme.Faint)), 12, 12);
        var app = selected;
        var icon = new Image { Width = S(34), Height = S(34) };
        if (app.Icon is { } path) _ = Thumb(path, icon);
        var head = Columns(12, (icon, null), (V(1, Text(app.Name, 15, weight: FontWeights.Bold, display: true),
                                                Text(string.Join(" · ", new[] { app.Version, app.Publisher }.Where(s => s.Length > 0)), 9.5, Theme.Faint)), 1));
        var rows = V(4);
        long total = app.Size;
        if (app.Size > 0) rows.Children.Add(Columns(8, (Text("Installed size", 9.5, Theme.Dim), 1), (Text(Format.Bytes(app.Size), 9.5, weight: FontWeights.SemiBold, mono: true), null)));
        if (leftovers is null) rows.Children.Add(Text("Looking for leftovers…", 9.5, Theme.Faint));
        else
        {
            foreach (var (folder, size) in leftovers)
            {
                total += size;
                rows.Children.Add(Columns(8, (Text(Tilde(folder), 9.5, Theme.Dim), 1), (Text(Format.Bytes(size), 9.5, weight: FontWeights.SemiBold, mono: true), null)));
            }
            if (leftovers.Count == 0) rows.Children.Add(Text("No leftover folders found", 9.5, Theme.Faint));
        }
        var uninstall = PillButton("Uninstall", Theme.Red, () => Uninstaller.Run(app), Glyphs.Delete);
        var clean = leftovers is { Count: > 0 }
            ? PillButton("Recycle leftovers", Theme.Accent2, () => { foreach (var (f, _) in leftovers) Uninstaller.Trash(f); Select(app); })
            : null;
        var foot = Columns(8, (Text($"{(leftovers?.Count ?? 0) + 1} items · {Format.Bytes(total)}", 10.5, weight: FontWeights.SemiBold), 1), (clean, null), (uninstall, null));
        return Card(Rows(10, (head, null), (Scroll(rows), 1), (foot, null)), 14, 12);
    }

    private void Large()
    {
        if (large is not null)
        {
            bar.Children.Add(Pill($"{large.Count} files · {Format.Bytes(large.Sum(f => f.Size))}", Theme.Dim));
            bar.Children.Add(PillButton("Rescan", Theme.Accent2, ScanLarge, Glyphs.Refresh));
        }
        if (large is null)
        {
            var start = PillButton(scanning ? "Scanning…" : "Scan", Theme.Accent, ScanLarge, Glyphs.Search);
            body.Children.Add(Card(Center(V(8, Center(Text("Files of 500 MB and up, and installers left in Downloads", 10.5, Theme.Dim)), Center(start))), 12, 12));
            return;
        }
        var list = V(4);
        foreach (var file in large.Take(80))
        {
            var texts = V(1, Text(Path.GetFileName(file.Path), 10.5, weight: FontWeights.SemiBold), Text(Tilde(Path.GetDirectoryName(file.Path) ?? ""), 8.5, Theme.Faint));
            var tag = file.Installer ? Pill("Installer", Theme.Amber) : null;
            var row = Columns(10, (texts, 1), (tag, null), (Text(Format.Bytes(file.Size), 10, weight: FontWeights.SemiBold, mono: true), null),
                              (PillButton("Show", Theme.Dim, () => Process.Start("explorer.exe", $"/select,\"{file.Path}\"")), null),
                              (PillButton("Recycle", Theme.Red, () => { LargeFiles.Trash(file.Path); large.Remove(file); Refresh(); }), null));
            list.Children.Add(Card(row, 8, 10));
        }
        if (large.Count == 0) list.Children.Add(Text("Nothing that big here", 10.5, Theme.Faint));
        body.Children.Add(Scroll(list));
    }

    private void ScanLarge()
    {
        if (scanning) return;
        scanning = true;
        Refresh();
        _ = Task.Run(LargeFiles.Scan).ContinueWith(t => Dispatch(() =>
        {
            scanning = false;
            large = t.IsCompletedSuccessfully ? t.Result : [];
            Refresh();
        }), TaskScheduler.Default);
    }

    private void Mirror()
    {
        var open = PillButton("Open Camera", Theme.Accent, Controls.Camera, Glyphs.Camera);
        body.Children.Add(Card(Center(V(8, Center(Icon(Glyphs.Camera, 22, Theme.Faint)), Center(Text("A quick look before a call", 12, Theme.Dim, FontWeights.SemiBold)),
                                         Center(Text("Opens Windows' Camera app; nothing is recorded by Beanotch", 9.5, Theme.Faint)), Center(open))), 12, 12));
    }

    private static string Tilde(string path)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        return path.StartsWith(home, StringComparison.OrdinalIgnoreCase) ? "~" + path[home.Length..] : path;
    }

    private static async Task Thumb(string path, Image target)
    {
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(path);
            using var thumbnail = await file.GetThumbnailAsync(ThumbnailMode.SingleItem, 48);
            var bitmap = new BitmapImage();
            await bitmap.SetSourceAsync(thumbnail);
            target.Source = bitmap;
        }
        catch (Exception) { }
    }
}
