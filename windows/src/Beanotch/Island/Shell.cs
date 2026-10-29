using Beanotch.Pages;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media.Animation;
using static Beanotch.Ui.Ui;

namespace Beanotch.Island;

// The open panel, in the layout picked in Settings (top tabs by default: the pages along the top, the page underneath).
// Settings and Tools open in a window of their own, from the gear.
public sealed class Shell
{
    private readonly Model model;
    private readonly Action applyTheme;
    private readonly Grid view = new();
    private readonly Dictionary<Tab, PanelPage> pages = [];
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
        glance = null;
        bar = null;
        Build();
        Shown();
    }

    private PanelLayout Layout => model.Settings.Layout;
    private Panel nav = new StackPanel();
    private Button? back;
    // In the Launcher layout: the grid of tiles shows until a page is picked, and again each time the panel opens.
    private bool grid = true;
    // Slide: which way the next page comes in, and the sideways swipe being counted.
    private int slideFrom;
    private double swipe;
    private bool swiped;
    private DateTime swipeAt;

    private void Build()
    {
        view.Children.Clear();
        title = Text("", 15, weight: FontWeights.Bold, display: true);
        date = Text("", 9.5, Theme.Faint, FontWeights.Medium);
        pills = H(6);
        host = new Grid { ChildrenTransitions = Arrive() };
        // The header's end: what's coming up, then the way to Settings and Tools.
        var extras = H(6, pills, IconButton(Glyphs.Settings, () => model.OpenSettings(Tab.Settings), 10, Theme.Dim, "Settings and tools"));
        back = null;
        FrameworkElement layout;
        switch (Layout)
        {
            case PanelLayout.Compact:
            {
                nav = V(2);
                var rail = Card(nav, 4, 12);
                rail.VerticalAlignment = VerticalAlignment.Stretch;
                layout = Columns(10, (rail, null), (Rows(8, (Header(extras), null), (host, 1)), 1));
                break;
            }
            case PanelLayout.TopTabs:
            {
                nav = H(2);
                var tray = new Border
                {
                    Child = new ScrollViewer { Content = nav, HorizontalScrollBarVisibility = ScrollBarVisibility.Hidden, VerticalScrollBarVisibility = ScrollBarVisibility.Disabled, HorizontalScrollMode = ScrollMode.Enabled, VerticalScrollMode = ScrollMode.Disabled },
                    Padding = new Thickness(S(2)), CornerRadius = new CornerRadius(S(9)),
                    Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.06)), HorizontalAlignment = HorizontalAlignment.Left,
                };
                var top = Columns(8, (tray, 1), (extras, null));
                layout = Rows(8, (top, null), (host, 1));
                break;
            }
            case PanelLayout.Bar:
            {
                // One slim row, its own gear at the end.
                nav = new StackPanel();
                layout = host;
                break;
            }
            case PanelLayout.Glance:
            {
                // One page of cards, no menu: the way to Settings under it.
                nav = new StackPanel();
                var gear = IconButton(Glyphs.Settings, () => model.OpenSettings(Tab.Settings), 9, Theme.Faint, "Settings and tools", 20);
                gear.HorizontalAlignment = HorizontalAlignment.Right;
                layout = Rows(6, (host, 1), (gear, null));
                break;
            }
            case PanelLayout.Slide:
            {
                // No menu: the page, a dot for each page under it, and a sideways swipe to move between them.
                nav = H(2);
                nav.HorizontalAlignment = HorizontalAlignment.Center;
                var gear = IconButton(Glyphs.Settings, () => model.OpenSettings(Tab.Settings), 9, Theme.Faint, "Settings and tools", 20);
                gear.HorizontalAlignment = HorizontalAlignment.Right;
                var dots = new Grid { Height = S(18), Children = { nav, gear } };
                host.AddHandler(UIElement.PointerWheelChangedEvent, new PointerEventHandler(Swiped), true);
                layout = Rows(6, (host, 1), (dots, null));
                break;
            }
            case PanelLayout.Classic:
            {
                nav = H(4);
                var top = Columns(8, (H(8, title, date), 1), (extras, null), (nav, null));
                top.Height = S(28);
                layout = Rows(8, (top, null), (host, 1));
                break;
            }
            case PanelLayout.Launcher:
            {
                nav = new StackPanel();
                back = IconButton("\uE72B", () => { grid = true; Show(); }, 10, Theme.Ink, "All pages");
                var top = Columns(8, (back, null), (H(8, title, date), 1), (extras, null));
                top.Height = S(26);
                layout = Rows(8, (top, null), (host, 1));
                break;
            }
            default:
            {
                nav = V(1);
                var side = Card(nav, 5, 12);
                side.Width = S(138);
                side.VerticalAlignment = VerticalAlignment.Stretch;
                layout = Columns(12, (side, null), (Rows(8, (Header(extras), null), (host, 1)), 1));
                break;
            }
        }
        var frame = new Border { Child = layout, Padding = new Thickness(S(12), S(10), S(12), S(12)) };
        view.Children.Add(frame);
        Open(model.Tab);
    }

    private Grid Header(UIElement extras)
    {
        var header = Columns(8, (H(8, title, date), 1), (extras, null));
        header.Height = S(26);
        return header;
    }

    // The tabs in order, with their icons, names and a word of status.
    private IEnumerable<(Tab Tab, string Glyph, string Name, string? Badge)> Entries()
    {
        yield return (Tab.Home, Glyphs.Home, "Overview", null);
        yield return (Tab.Today, Glyphs.Calendar, "Today", null);
        yield return (Tab.Prayer, Glyphs.Moon, "Prayer", Model.Clock(model.NextPrayer.Time));
        yield return (Tab.Music, Glyphs.Music, "Music", model.Media.Playing ? "• Live" : null);
        yield return (Tab.Shelf, Glyphs.Shelf, "Shelf", model.Shelf.Items.Count > 0 ? $"{model.Shelf.Items.Count}" : null);
        yield return (Tab.Clipboard, Glyphs.Clipboard, "Clipboard", model.Clipboard.Items.Count > 0 ? $"{model.Clipboard.Items.Count}" : null);
        yield return (Tab.Ai, Glyphs.Spark, "AI", null);
        yield return (Tab.Controls, Glyphs.Controls, "Controls", null);
    }

    private GlancePage? glance;
    private BarPage? bar;

    // The page showing: Glance's cards, Bar's row, or the open tab's page.
    private PanelPage Current => Layout switch
    {
        PanelLayout.Glance => glance ??= new GlancePage(model),
        PanelLayout.Bar => bar ??= new BarPage(model),
        _ => PageFor(model.Tab),
    };

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
        if (tab is Tab.Tools or Tab.Settings)
        {
            model.OpenSettings(tab);
            return;
        }
        if (!model.Visible(tab)) tab = model.Pages[0];
        // In Slide, the new page comes in from the side it sits on.
        var pages = model.Pages;
        slideFrom = Math.Sign(pages.IndexOf(tab) - pages.IndexOf(model.Tab));
        model.Tab = tab;
        grid = false;
        Show();
    }

    private void Show()
    {
        host.Children.Clear();
        if (Layout == PanelLayout.Launcher && grid)
        {
            host.Children.Add(Tiles());
        }
        else
        {
            var page = Current;
            if (Layout == PanelLayout.Slide)
                host.ChildrenTransitions = [new EntranceThemeTransition { FromHorizontalOffset = slideFrom * S(60), FromVerticalOffset = 0 }];
            host.Children.Add(page.View);
            page.Refresh();
        }
        if (back is not null) back.Visibility = grid ? Visibility.Collapsed : Visibility.Visible;
        BuildSidebar();
        Tick();
    }

    public void Shown()
    {
        if (Layout == PanelLayout.Launcher) grid = true;
        Show();
    }

    // The Launcher's grid: a tile per page, five across.
    private FrameworkElement Tiles()
    {
        var wrap = new VariableSizedWrapGrid { Orientation = Orientation.Horizontal, MaximumRowsOrColumns = 5, ItemWidth = S(122), ItemHeight = S(84) };
        foreach (var (tab, glyph, name, badge) in Entries().Where(e => model.Visible(e.Tab)))
        {
            var content = V(6, Icon(glyph, 18, Theme.Accent), Text(name, 11, weight: FontWeights.SemiBold), badge is null ? null : Text(badge, 8.5, Theme.Faint));
            content.HorizontalAlignment = HorizontalAlignment.Center;
            content.VerticalAlignment = VerticalAlignment.Center;
            var tile = Plain(new Grid { Children = { content } }, () => Open(tab), Theme.Surface, 14);
            tile.HorizontalAlignment = HorizontalAlignment.Stretch;
            tile.VerticalAlignment = VerticalAlignment.Stretch;
            tile.Margin = new Thickness(0, 0, S(8), S(8));
            wrap.Children.Add(tile);
        }
        return Scroll(wrap);
    }

    public void Update()
    {
        if (!(Layout == PanelLayout.Launcher && grid)) Current.Refresh();
    }

    public void Tick()
    {
        title.Text = Layout == PanelLayout.Launcher && grid ? "Beanotch" : Model.Title(model.Tab);
        date.Text = DateTime.Now.ToString("dddd, d MMMM") + (model.Visible(Tab.Prayer) ? " · " + model.Hijri : "");
        pills.Children.Clear();
        var next = model.NextPrayer;
        if (model.Visible(Tab.Prayer)) pills.Children.Add(Pill($"{next.Name} {Model.Clock(next.Time)}", Theme.Accent2, Glyphs.Moon));
        // Cleanup news belongs with Overview; without that page, the header keeps quiet about it.
        if (model.Cleaner.Total > 0 && model.Visible(Tab.Home)) pills.Children.Add(Pill($"{Format.Bytes(model.Cleaner.Total)} can be freed", Theme.Amber, dot: true));
        if (!(Layout == PanelLayout.Launcher && grid)) Current.Tick();
    }

    private void BuildSidebar()
    {
        nav.Children.Clear();
        if (Layout == PanelLayout.Launcher) return;
        if (Layout == PanelLayout.Slide)
        {
            foreach (var tab in model.Pages) Dot(tab);
            return;
        }
        if (Layout != PanelLayout.Studio)
        {
            foreach (var (tab, glyph, name, _) in Entries()) Compact(tab, glyph, name);
            return;
        }
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
        SettingsItem();
    }

    // Studio's last row: Settings and Tools, in their own window.
    private void SettingsItem()
    {
        var row = Columns(7, (Icon(Glyphs.Settings, 10, Theme.Dim), null),
                          (Text("Settings", 10.5, Theme.WithAlpha(Theme.Ink, 0.75)), 1),
                          (Icon("\uE8A7", 8, Theme.Faint), null));
        row.Height = S(20);
        row.Padding = new Thickness(S(8), 0, S(8), 0);
        var button = Plain(row, () => model.OpenSettings(Tab.Settings), Colors.Transparent, 7);
        button.HorizontalAlignment = HorizontalAlignment.Stretch;
        nav.Children.Add(button);
    }

    // A page's dot under Slide's pages: long for the open one.
    private void Dot(Tab tab)
    {
        var active = model.Tab == tab;
        var dot = new Border
        {
            Width = S(active ? 16 : 6), Height = S(6), CornerRadius = new CornerRadius(S(3)),
            Background = Theme.Brush(active ? Theme.Accent : Theme.WithAlpha(Theme.Ink, 0.22)),
        };
        nav.Children.Add(Plain(new Grid { Padding = new Thickness(S(3)), Children = { dot } }, () => Open(tab), Colors.Transparent, 4, tip: Model.Title(tab)));
    }

    // A sideways two-finger swipe (or a tilt of the wheel) turns one page per gesture; a pause ends the gesture.
    private void Swiped(object sender, PointerRoutedEventArgs e)
    {
        var point = e.GetCurrentPoint(host).Properties;
        if (!point.IsHorizontalMouseWheel) return;
        var now = DateTime.UtcNow;
        if (now - swipeAt > TimeSpan.FromMilliseconds(350)) { swipe = 0; swiped = false; }
        swipeAt = now;
        e.Handled = true;
        if (swiped) return;
        swipe += point.MouseWheelDelta;
        if (Math.Abs(swipe) < 100) return;
        swiped = true;
        var pages = model.Pages;
        var at = pages.IndexOf(model.Tab) + Math.Sign(swipe);
        if (at >= 0 && at < pages.Count) Open(pages[at]);
    }

    // A tab in the other layouts: an icon in the rail, an icon and its name along the top, or a round button.
    private void Compact(Tab tab, string glyph, string name)
    {
        if (!model.Visible(tab)) return;
        var active = model.Tab == tab;
        var color = active ? Theme.Accent : Theme.Dim;
        Button button = Layout switch
        {
            PanelLayout.TopTabs => Plain(H(5, Icon(glyph, 9, color), Text(name, 9.5, active ? Theme.Ink : Theme.Dim, active ? FontWeights.SemiBold : FontWeights.Medium)),
                                         () => Open(tab), active ? Theme.Thumb : Colors.Transparent, 7, new Thickness(S(9), S(4), S(9), S(4)), name),
            PanelLayout.Classic => IconButton(glyph, () => Open(tab), 10, color, name, 26),
            _ => IconButton(glyph, () => Open(tab), 11, color, name, 30),
        };
        if (Layout == PanelLayout.Classic && active) button.Background = Theme.Brush(Theme.WithAlpha(Theme.Accent, 0.16));
        if (Layout == PanelLayout.Compact && active) button.Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.08));
        nav.Children.Add(button);
    }

    private void Group(string name)
    {
        var label = Text(name, 8, Theme.Faint, FontWeights.SemiBold);
        label.CharacterSpacing = 120;
        label.Margin = new Thickness(S(8), S(5), 0, S(1));
        nav.Children.Add(label);
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
        nav.Children.Add(button);
    }
}
