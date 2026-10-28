using System.Diagnostics;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage;
using Windows.Storage.FileProperties;
using Windows.Storage.Pickers;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Files kept at hand: drop them on the island, drag them out into any app later.
public sealed class ShelfPage(Model model) : PanelPage(model)
{
    private readonly StackPanel bar = H(6);
    private readonly Grid body = new();
    private bool phone => Model.Phone.Running || Model.Phone.Problem is not null;

    protected override FrameworkElement Build() => Rows(8, (bar, null), (body, 1));

    public override void Refresh()
    {
        var shelf = Model.Shelf;
        bar.Children.Clear();
        bar.Children.Add(Pill("Drop & drag out", Theme.Accent2, ""));
        bar.Children.Add(Pill($"{shelf.Items.Count} files", Theme.Dim));
        bar.Children.Add(new Border { Width = S(12) });
        bar.Children.Add(IconButton(Glyphs.Grid, () => { shelf.Grid = true; Refresh(); }, 10, shelf.Grid ? Theme.Ink : Theme.Faint, "Grid"));
        bar.Children.Add(IconButton(Glyphs.List, () => { shelf.Grid = false; Refresh(); }, 10, shelf.Grid ? Theme.Faint : Theme.Ink, "List"));
        bar.Children.Add(PillButton(phone ? "Done" : "Phone", Theme.Accent, () =>
        {
            if (phone) Model.Phone.Stop(); else Model.Phone.Start();
            Refresh();
        }, "\uE8EA"));
        bar.Children.Add(PillButton("Add Files", Theme.Accent2, () => _ = PickAsync(), Glyphs.Add));
        if (shelf.Items.Count > 0) bar.Children.Add(PillButton("Clear All", Theme.Dim, () => { shelf.Clear(); Refresh(); }));

        body.Children.Clear();
        if (phone)
        {
            body.Children.Add(PhonePanel());
            return;
        }
        if (shelf.Items.Count == 0)
        {
            var empty = V(6, Center(Icon("", 20, Theme.Faint)), Center(Text("Drop files on the island to keep them handy", 11, Theme.Faint, FontWeights.Medium)));
            var zone = Card(Center(empty), 10, 14);
            zone.BorderBrush = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.12));
            body.Children.Add(zone);
            return;
        }
        var list = shelf.Grid ? GridView(shelf.Items) : ListView(shelf.Items);
        body.Children.Add(Scroll(list));
    }

    // The QR to scan, and how to use it.
    private FrameworkElement PhonePanel()
    {
        var drop = Model.Phone;
        if (drop.Problem is { } problem || drop.Address is null)
            return Card(Center(Text(drop.Problem ?? "Starting…", 11, Theme.Faint, FontWeights.Medium)), 10, 14);
        var qr = new Image { Width = S(132), Height = S(132), Stretch = Stretch.Fill, Source = QrImage(drop.Address) };
        var tile = new Border { Child = qr, Background = Theme.Brush(Theme.Rgb(1, 1, 1)), CornerRadius = new CornerRadius(S(10)), Padding = new Thickness(S(6)) };
        var text = V(6,
            Text("Scan with your phone's camera", 13, weight: FontWeights.SemiBold),
            Text("On the same Wi-Fi. Send photos and files here, or download what's on the Shelf. Nothing to install on the phone.", 9.5, Theme.Dim, wrap: true),
            Text(drop.Address, 9, Theme.Faint, mono: true),
            drop.Received > 0 ? Pill($"{drop.Received} received", Theme.Accent, dot: true) : null,
            Text("Windows may ask once to let Beanotch through the firewall: allow it on private networks.", 8.5, Theme.Faint, wrap: true));
        text.VerticalAlignment = VerticalAlignment.Center;
        return Card(Columns(16, (tile, null), (text, 1)), 12, 14);
    }

    private static WriteableBitmap? QrImage(string text)
    {
        if (QrCode.Encode(text) is not { } modules) return null;
        // Eight pixels a module, so scaling it down for the screen stays crisp.
        const int scale = 8;
        int n = modules.GetLength(0), quiet = 2, size = (n + quiet * 2) * scale;
        var pixels = new byte[size * size * 4];
        for (var y = 0; y < size; y++)
            for (var x = 0; x < size; x++)
            {
                int mx = x / scale - quiet, my = y / scale - quiet;
                var dark = mx >= 0 && my >= 0 && mx < n && my < n && modules[my, mx];
                var i = (y * size + x) * 4;
                pixels[i] = pixels[i + 1] = pixels[i + 2] = dark ? (byte)0 : (byte)255;
                pixels[i + 3] = 255;
            }
        var image = new WriteableBitmap(size, size);
        using (var stream = System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeBufferExtensions.AsStream(image.PixelBuffer)) stream.Write(pixels, 0, pixels.Length);
        image.Invalidate();
        return image;
    }

    private FrameworkElement GridView(IEnumerable<string> paths)
    {
        var wrap = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, ItemWidth = S(132), ItemHeight = S(138) };
        foreach (var path in paths)
        {
            var thumb = new Grid { Height = S(70), CornerRadius = new CornerRadius(S(8)), Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.05)) };
            var image = new Image { Stretch = Stretch.UniformToFill };
            thumb.Children.Add(image);
            var ext = Path.GetExtension(path).TrimStart('.').ToUpperInvariant();
            if (ext.Length > 0)
            {
                var tag = Pill(ext, Theme.Ink);
                tag.HorizontalAlignment = HorizontalAlignment.Left;
                tag.VerticalAlignment = VerticalAlignment.Top;
                tag.Margin = new Thickness(S(6));
                tag.Background = Theme.Brush(Theme.WithAlpha(Theme.Background, 0.8));
                thumb.Children.Add(tag);
            }
            var remove = IconButton(Glyphs.Close, () => { Model.Shelf.Remove(path); Refresh(); }, 7, Theme.Ink, "Remove", 18);
            remove.HorizontalAlignment = HorizontalAlignment.Right;
            remove.VerticalAlignment = VerticalAlignment.Top;
            remove.Margin = new Thickness(S(4));
            thumb.Children.Add(remove);
            _ = LoadThumbnailAsync(path, image, 192);

            var actions = H(4,
                IconButton(Glyphs.OpenFile, () => OpenFile(path), 9, Theme.Dim, "Open", 22),
                IconButton(Glyphs.Folder, () => Reveal(path), 9, Theme.Dim, "Show in folder", 22));
            var card = Card(V(5, thumb, Text(Path.GetFileName(path), 10, weight: FontWeights.SemiBold),
                              Text(Size(path) + " · Drag out ready", 8.5, Theme.Accent2), actions), 7, 12);
            card.Margin = new Thickness(0, 0, S(8), S(8));
            Draggable(card, path);
            wrap.Children.Add(card);
        }
        return wrap;
    }

    private FrameworkElement ListView(IEnumerable<string> paths)
    {
        var list = V(6);
        foreach (var path in paths)
        {
            var icon = new Image { Width = S(28), Height = S(28), Stretch = Stretch.UniformToFill };
            _ = LoadThumbnailAsync(path, icon, 64);
            var iconBox = new Border { Child = icon, CornerRadius = new CornerRadius(S(6)), Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.05)) };
            var texts = V(1, Text(Path.GetFileName(path), 11, weight: FontWeights.SemiBold), Text(Size(path), 8.5, Theme.Faint));
            var row = Columns(10, (iconBox, null), (texts, 1),
                              (PillButton("Open", Theme.Dim, () => OpenFile(path)), null),
                              (PillButton("Folder", Theme.Dim, () => Reveal(path)), null),
                              (IconButton(Glyphs.Close, () => { Model.Shelf.Remove(path); Refresh(); }, 8, Theme.Dim, "Remove"), null));
            var card = Card(row, 8, 10);
            Draggable(card, path);
            list.Children.Add(card);
        }
        return list;
    }

    // Dragging a card hands the real file to the drop target, the same as dragging it from Explorer.
    private static void Draggable(UIElement element, string path)
    {
        element.CanDrag = true;
        element.DragStarting += async (_, e) =>
        {
            var deferral = e.GetDeferral();
            try
            {
                var file = await StorageFile.GetFileFromPathAsync(path);
                e.Data.SetStorageItems([file]);
                e.Data.RequestedOperation = DataPackageOperation.Copy;
            }
            catch (Exception) { e.Cancel = true; }
            finally { deferral.Complete(); }
        };
    }

    private static async Task LoadThumbnailAsync(string path, Image target, uint size)
    {
        try
        {
            var file = await StorageFile.GetFileFromPathAsync(path);
            using var thumbnail = await file.GetThumbnailAsync(ThumbnailMode.SingleItem, size);
            if (thumbnail is null) return;
            var bitmap = new BitmapImage();
            await bitmap.SetSourceAsync(thumbnail);
            target.Source = bitmap;
        }
        catch (Exception) { }
    }

    private static string Size(string path)
    {
        try { return Format.Bytes(new FileInfo(path).Length); }
        catch (Exception) { return "missing"; }
    }

    private static void OpenFile(string path)
    {
        try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); }
        catch (Exception) { }
    }

    private static void Reveal(string path)
    {
        try { Process.Start("explorer.exe", $"/select,\"{path}\""); }
        catch (Exception) { }
    }

    private async Task PickAsync()
    {
        var picker = new FileOpenPicker();
        picker.FileTypeFilter.Add("*");
        WinRT.Interop.InitializeWithWindow.Initialize(picker, Hwnd);
        var files = await picker.PickMultipleFilesAsync();
        if (files.Count == 0) return;
        Model.Shelf.Add(files.Select(f => f.Path));
        Refresh();
    }

    // The island's window handle, for the file picker; set by the window.
    public static nint Hwnd { get; set; }
}
