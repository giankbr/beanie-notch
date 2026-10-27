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
        bar.Children.Add(PillButton("Add Files", Theme.Accent2, () => _ = PickAsync(), Glyphs.Add));
        if (shelf.Items.Count > 0) bar.Children.Add(PillButton("Clear All", Theme.Dim, () => { shelf.Clear(); Refresh(); }));

        body.Children.Clear();
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
