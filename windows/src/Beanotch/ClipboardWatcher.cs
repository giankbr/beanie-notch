using System.Collections.ObjectModel;
using Windows.ApplicationModel.DataTransfer;

namespace Beanotch;

public sealed class ClipItem(string text, DateTimeOffset copied)
{
    public string Text { get; } = text;
    public DateTimeOffset Copied { get; set; } = copied;
    public string Preview
    {
        get
        {
            var line = Text.ReplaceLineEndings(" ").Trim();
            return line.Length > 140 ? line[..140] + "…" : line;
        }
    }
}

// Text history in memory only. Password managers mark what they copy with
// ExcludeClipboardContentFromMonitorProcessing, and those items are skipped.
public sealed class ClipboardWatcher
{
    private const int Limit = 50;
    private bool ownChange;

    public ObservableCollection<ClipItem> Items { get; } = [];

    public ClipboardWatcher() => Clipboard.ContentChanged += (_, _) => _ = CaptureAsync();

    private async Task CaptureAsync()
    {
        if (ownChange)
        {
            ownChange = false;
            return;
        }
        try
        {
            var content = Clipboard.GetContent();
            if (content.Contains("ExcludeClipboardContentFromMonitorProcessing") || !content.Contains(StandardDataFormats.Text)) return;
            var text = await content.GetTextAsync();
            if (string.IsNullOrWhiteSpace(text)) return;
            Add(text);
        }
        // Another app can hold the clipboard open for a moment.
        catch (Exception) { }
    }

    private void Add(string text)
    {
        var existing = Items.FirstOrDefault(i => i.Text == text);
        if (existing is not null) Items.Remove(existing);
        Items.Insert(0, existing ?? new ClipItem(text, DateTimeOffset.Now));
        Items[0].Copied = DateTimeOffset.Now;
        while (Items.Count > Limit) Items.RemoveAt(Items.Count - 1);
    }

    public void Copy(ClipItem item)
    {
        var package = new DataPackage();
        package.SetText(item.Text);
        ownChange = true;
        Clipboard.SetContent(package);
        Add(item.Text);
    }
}
