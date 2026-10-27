using Beanotch.Pages;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using static Beanotch.Ui.Ui;

namespace Beanotch.Island;

// The open panel in the Mac's Studio layout: a labelled side menu, a header with the page title and date, and the
// page underneath.
public sealed class Shell
{
    private readonly Model model;
    private readonly Action applyTheme;
    private readonly Grid view = new();
    private readonly Dictionary<Tab, PanelPage> pages = [];
    private StackPanel sidebar = new();
    private TextBlock title = new(), date = new();
    private StackPanel pills = new();
    private Grid host = new();

    public FrameworkElement View => view;

    public Shell(Model model, Action applyTheme)
    {
        this.model = model;
        this.applyTheme = applyTheme;
        Build();
    }

    // Everything is rebuilt when the theme or accent changes, since colours are baked into the elements.
    public void Rebuild()
    {
        applyTheme();
        pages.Clear();
        Build();
        Shown();
    }

    private void Build()
    {
        view.Children.Clear();
        sidebar = V(1);
        var side = Card(sidebar, 5, 12);
        side.Width = S(138);
        side.VerticalAlignment = VerticalAlignment.Stretch;

        title = Text("", 15, weight: FontWeights.Bold, display: true);
        date = Text("", 9.5, Theme.Faint, FontWeights.Medium);
        pills = H(6);
        var header = Columns(8, (H(8, title, date), 1), (pills, null));
        header.Height = S(26);

        host = new Grid();
        var right = Rows(8, (header, null), (host, 1));
        var layout = Columns(12, (side, null), (right, 1));
        layout.Padding = new Thickness(S(12), S(10), S(12), S(12));
        view.Children.Add(layout);
        Open(model.Tab);
    }

    private PanelPage PageFor(Tab tab)
    {
        if (pages.TryGetValue(tab, out var page)) return page;
        page = tab switch
        {
            Tab.Home => new HomePage(model),
            Tab.Today => new TodayPage(model, Open),
            Tab.Controls => new ControlsPage(model),
            Tab.Tools => new ToolsPage(model),
            Tab.Settings => new SettingsPage(model, model.Updater),
            Tab.Prayer => new PrayerPage(model),
            Tab.Music => new MusicPage(model),
            Tab.Shelf => new ShelfPage(model),
            Tab.Clipboard => new ClipboardPage(model),
            _ => new AiPage(model),
        };
        page.Rebuild = Rebuild;
        pages[tab] = page;
        return page;
    }

    public void Open(Tab tab)
    {
        if (!model.Visible(tab)) tab = Tab.Home;
        model.Tab = tab;
        host.Children.Clear();
        var page = PageFor(tab);
        host.Children.Add(page.View);
        page.Refresh();
        BuildSidebar();
        Tick();
    }

    public void Shown()
    {
        PageFor(model.Tab).Refresh();
        BuildSidebar();
        Tick();
    }

    public void Update() => PageFor(model.Tab).Refresh();

    public void Tick()
    {
        title.Text = Model.Title(model.Tab);
        date.Text = DateTime.Now.ToString("dddd, d MMMM") + (model.Visible(Tab.Prayer) ? " · " + model.Hijri : "");
        pills.Children.Clear();
        var next = model.NextPrayer;
        if (model.Visible(Tab.Prayer)) pills.Children.Add(Pill($"{next.Name} {Model.Clock(next.Time)}", Theme.Accent2, Glyphs.Moon));
        if (model.Cleaner.Total > 0) pills.Children.Add(Pill($"{Format.Bytes(model.Cleaner.Total)} can be freed", Theme.Amber, dot: true));
        PageFor(model.Tab).Tick();
    }

    private void BuildSidebar()
    {
        sidebar.Children.Clear();
        Item(Tab.Home, Glyphs.Home);
        Item(Tab.Today, Glyphs.Calendar);
        Item(Tab.Prayer, Glyphs.Moon, Model.Clock(model.NextPrayer.Time));
        Item(Tab.Music, Glyphs.Music, model.Media.Playing ? "• Live" : null);
        if (model.Visible(Tab.Shelf) || model.Visible(Tab.Clipboard)) Group("FILES");
        Item(Tab.Shelf, Glyphs.Shelf, model.Shelf.Items.Count > 0 ? $"{model.Shelf.Items.Count}" : null);
        Item(Tab.Clipboard, Glyphs.Clipboard, model.Clipboard.Items.Count > 0 ? $"{model.Clipboard.Items.Count}" : null);
        Group("SYSTEM");
        Item(Tab.Ai, Glyphs.Spark);
        Item(Tab.Controls, Glyphs.Controls);
        Item(Tab.Tools, Glyphs.Tools);
        Item(Tab.Settings, Glyphs.Settings);
    }

    private void Group(string name)
    {
        var label = Text(name, 8, Theme.Faint, FontWeights.SemiBold);
        label.CharacterSpacing = 120;
        label.Margin = new Thickness(S(8), S(5), 0, S(1));
        sidebar.Children.Add(label);
    }

    private void Item(Tab tab, string glyph, string? badge = null)
    {
        if (!model.Visible(tab)) return;
        var active = model.Tab == tab;
        var name = tab switch { Tab.Home => "Overview", Tab.Prayer => "Prayer", Tab.Music => "Music", Tab.Ai => "AI", _ => tab.ToString() };
        var badgeText = badge is null ? null : Text(badge, 8.5, badge.StartsWith('•') ? Theme.Accent : Theme.Faint, mono: !badge.StartsWith('•'));
        var row = Columns(7, (Icon(glyph, 10, active ? Theme.Accent : Theme.Dim), null),
                          (Text(name, 10.5, active ? Theme.Ink : Theme.WithAlpha(Theme.Ink, 0.75), active ? FontWeights.SemiBold : FontWeights.Normal), 1),
                          (badgeText, null));
        row.Height = S(20);
        row.Padding = new Thickness(S(8), 0, S(8), 0);
        var button = Plain(row, () => Open(tab), active ? Theme.WithAlpha(Theme.Ink, 0.08) : Colors.Transparent, 7);
        button.HorizontalAlignment = HorizontalAlignment.Stretch;
        sidebar.Children.Add(button);
    }
}
