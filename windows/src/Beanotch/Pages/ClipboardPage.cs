using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Clipboard history: search, pin, and click to copy again.
public sealed class ClipboardPage(Model model) : PanelPage(model)
{
    private readonly TextBox search = new() { PlaceholderText = "Search text you copied" };
    private readonly StackPanel bar = H(6);
    private readonly StackPanel list = V(5);
    private readonly Grid body = new();
    private ClipItem? copied;
    private int shownCount = -1;

    protected override FrameworkElement Build()
    {
        search.FontSize = S(10.5);
        search.TextChanged += (_, _) => Fill();
        Model.Clipboard.Items.CollectionChanged += (_, _) => { if (Model.Expanded && Model.Tab == Tab.Clipboard) Fill(); };
        var top = Columns(8, (search, 1), (bar, null));
        var hint = Text("Click an item to copy it again · pinned items stay", 8.5, Theme.Faint);
        hint.HorizontalAlignment = HorizontalAlignment.Center;
        body.Children.Add(Scroll(list));
        return Rows(8, (top, null), (body, 1), (hint, null));
    }

    public override void Refresh() => Fill();

    public override void Tick()
    {
        if (Model.Clipboard.Items.Count != shownCount) Fill();
    }

    private void Fill()
    {
        var clipboard = Model.Clipboard;
        shownCount = clipboard.Items.Count;
        bar.Children.Clear();
        bar.Children.Add(Pill($"{clipboard.Items.Count} items", Theme.Dim));
        bar.Children.Add(PillButton("Clear", Theme.Dim, () => { clipboard.Clear(); Fill(); }));

        list.Children.Clear();
        if (!Model.Settings.ClipboardHistory)
        {
            list.Children.Add(Empty("Clipboard history is off", "Turn it on in Overview › Quick settings"));
            return;
        }
        var query = search.Text.Trim();
        var items = clipboard.Items.Where(i => query.Length == 0 || (i.Text?.Contains(query, StringComparison.OrdinalIgnoreCase) ?? false)).ToList();
        if (items.Count == 0)
        {
            list.Children.Add(query.Length > 0 ? Empty("Nothing matches", "Try another word") : Empty("Nothing copied yet", "Copy some text or an image"));
            return;
        }
        foreach (var item in items) list.Children.Add(RowFor(item));
    }

    private UIElement RowFor(ClipItem item)
    {
        UIElement lead = item.Image is not null
            ? new Border { Width = S(34), Height = S(22), CornerRadius = new CornerRadius(S(4)), Child = new Image { Source = item.Image, Stretch = Stretch.UniformToFill } }
            : Icon(Glyphs.Copy, 10, Theme.Dim);
        var text = Text(item.Preview, 11, weight: FontWeights.Medium);
        var age = Text(copied == item ? "Copied" : Ago(item.Copied), 8.5, copied == item ? Theme.Good : Theme.Faint, mono: true);
        var pin = item.Text is null ? null : IconButton(Glyphs.Pin, () => { Model.Clipboard.TogglePin(item); Fill(); }, 9,
                                                       item.Pinned ? Theme.Amber : Theme.Faint, item.Pinned ? "Unpin" : "Pin", 22);
        var row = Columns(10, (lead, null), (text, 1), (age, null), (pin, null));
        row.Padding = new Thickness(S(10), S(7), S(10), S(7));
        var button = Plain(row, () =>
        {
            Model.Clipboard.Copy(item);
            copied = item;
            Fill();
        }, item.Pinned ? Theme.WithAlpha(Theme.Accent, 0.1) : Theme.Surface, 10);
        button.HorizontalAlignment = HorizontalAlignment.Stretch;
        return button;
    }

    private static UIElement Empty(string title, string caption)
    {
        var panel = V(4, Center(Icon(Glyphs.Clipboard, 18, Theme.Faint)), Center(Text(title, 12, Theme.Dim, FontWeights.SemiBold)), Center(Text(caption, 9.5, Theme.Faint)));
        panel.Margin = new Thickness(0, S(50), 0, 0);
        return panel;
    }

    private static string Ago(DateTimeOffset at)
    {
        var span = DateTimeOffset.Now - at;
        return span.TotalMinutes < 1 ? "now" : span.TotalHours < 1 ? $"{(int)span.TotalMinutes}m ago"
             : span.TotalDays < 1 ? $"{(int)span.TotalHours}h ago" : $"{(int)span.TotalDays}d ago";
    }
}
