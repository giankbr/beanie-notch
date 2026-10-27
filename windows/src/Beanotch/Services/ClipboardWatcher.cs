using System.Collections.ObjectModel;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.ApplicationModel.DataTransfer;
using Windows.Storage.Streams;

namespace Beanotch.Services;

public sealed class ClipItem
{
    public string? Text { get; init; }
    public BitmapImage? Image { get; init; }
    public RandomAccessStreamReference? ImageSource { get; init; }
    public int ImageWidth { get; init; }
    public int ImageHeight { get; init; }
    public DateTimeOffset Copied { get; set; } = DateTimeOffset.Now;
    public bool Pinned { get; set; }

    public string Preview
    {
        get
        {
            if (Text is null) return $"Image · {ImageWidth}×{ImageHeight}";
            var line = Text.ReplaceLineEndings(" ").Trim();
            return line.Length > 160 ? line[..160] + "…" : line;
        }
    }
}

// Text and image history, kept in memory; pinned text is saved. Password managers mark what they copy with
// ExcludeClipboardContentFromMonitorProcessing, and those items are skipped.
public sealed class ClipboardWatcher
{
    private const int Limit = 100;
    private readonly AppSettings settings;
    private bool ownChange;

    public ObservableCollection<ClipItem> Items { get; } = [];

    public ClipboardWatcher(AppSettings settings)
    {
        this.settings = settings;
        foreach (var text in settings.Pinned) Items.Add(new ClipItem { Text = text, Pinned = true });
        Clipboard.ContentChanged += (_, _) => _ = CaptureAsync();
    }

    private async Task CaptureAsync()
    {
        if (ownChange)
        {
            ownChange = false;
            return;
        }
        if (!settings.ClipboardHistory) return;
        try
        {
            var content = Clipboard.GetContent();
            if (content.Contains("ExcludeClipboardContentFromMonitorProcessing")) return;
            if (content.Contains(StandardDataFormats.Text))
            {
                var text = await content.GetTextAsync();
                if (!string.IsNullOrWhiteSpace(text))
                {
                    AddText(text);
                    Copied?.Invoke(text);
                }
            }
            else if (content.Contains(StandardDataFormats.Bitmap))
            {
                var reference = await content.GetBitmapAsync();
                using var stream = await reference.OpenReadAsync();
                var image = new BitmapImage();
                await image.SetSourceAsync(stream);
                Insert(new ClipItem { Image = image, ImageSource = reference, ImageWidth = image.PixelWidth, ImageHeight = image.PixelHeight });
            }
        }
        // Another app can hold the clipboard open for a moment.
        catch (Exception) { }
    }

    private void AddText(string text)
    {
        var existing = Items.FirstOrDefault(i => i.Text == text);
        if (existing is not null)
        {
            Items.Remove(existing);
            existing.Copied = DateTimeOffset.Now;
            Insert(existing);
            return;
        }
        Insert(new ClipItem { Text = text });
    }

    // Pinned items stay on top; the newest unpinned item comes right after them.
    private void Insert(ClipItem item)
    {
        var at = item.Pinned ? 0 : Items.Count(i => i.Pinned);
        Items.Insert(at, item);
        while (Items.Count > Limit)
        {
            var last = Items.LastOrDefault(i => !i.Pinned);
            if (last is null) break;
            Items.Remove(last);
        }
    }

    // New text copied anywhere, for Smart copy.
    public event Action<string>? Copied;

    // Text onto the clipboard without it counting as a new copy.
    public void CopyText(string text)
    {
        var package = new DataPackage();
        package.SetText(text);
        ownChange = true;
        Clipboard.SetContent(package);
    }

    public void Copy(ClipItem item)
    {
        var package = new DataPackage();
        if (item.Text is not null) package.SetText(item.Text);
        else if (item.ImageSource is not null) package.SetBitmap(item.ImageSource);
        else return;
        ownChange = true;
        Clipboard.SetContent(package);
    }

    public void TogglePin(ClipItem item)
    {
        if (item.Text is null) return;
        Items.Remove(item);
        item.Pinned = !item.Pinned;
        Insert(item);
        SavePins();
    }

    public void Remove(ClipItem item)
    {
        Items.Remove(item);
        if (item.Pinned) SavePins();
    }

    public void Clear()
    {
        foreach (var item in Items.Where(i => !i.Pinned).ToList()) Items.Remove(item);
    }

    private void SavePins()
    {
        settings.Pinned = [.. Items.Where(i => i.Pinned && i.Text is not null).Select(i => i.Text!)];
        settings.Save();
    }
}
