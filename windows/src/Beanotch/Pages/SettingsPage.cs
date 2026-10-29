using Beanotch.Core;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Settings, laid out like the Mac's: sections down the side, one at a time on the right. It lives in its own window,
// with Tools as its last section.
public sealed class SettingsPage(Model model, Updater updater) : PanelPage(model)
{
    public enum Section { Appearance, Pages, Idle, Island, Today, Prayer, System, Tools }

    private readonly StackPanel sections = V(1);
    private readonly Grid content = new() { ChildrenTransitions = Arrive() };
    private readonly Grid footer = new();
    // Kept across rebuilds (a theme change makes a new page), and set by the window to open on Tools.
    private static Section section = Section.Appearance;
    public static Section? Opening { get; set; }
    private ToolsPage? tools;

    protected override FrameworkElement Build()
    {
        sections.Width = S(124);
        footer.Width = S(124);
        var divider = new Border { Width = 1, Background = Theme.Brush(Theme.Stroke) };
        return Columns(12, (Rows(0, (sections, 1), (footer, null)), null), (divider, null), (content, 1));
    }

    public override void Refresh()
    {
        if (Opening is { } opening) { section = opening; Opening = null; }
        sections.Children.Clear();
        foreach (var s in Enum.GetValues<Section>())
        {
            var active = s == section;
            var glyph = s switch
            {
                Section.Appearance => "", Section.Pages => "", Section.Island => "", Section.Idle => "\uE708",
                Section.Today => Glyphs.Calendar, Section.Prayer => Glyphs.Moon, Section.Tools => Glyphs.Tools, _ => Glyphs.Settings,
            };
            var row = Columns(7, (Icon(glyph, 10, active ? Theme.Accent : Theme.Dim), null),
                              (Text(s == Section.Island ? "In the island" : s.ToString(), 10.5, active ? Theme.Ink : Theme.WithAlpha(Theme.Ink, 0.75),
                                    active ? FontWeights.SemiBold : FontWeights.Normal), 1));
            row.Height = S(21);
            row.Padding = new Thickness(S(8), 0, S(8), 0);
            var b = Plain(row, () => { section = s; Refresh(); }, active ? Theme.WithAlpha(Theme.Ink, 0.08) : Ui.Ui.Transparent, 7);
            b.HorizontalAlignment = HorizontalAlignment.Stretch;
            sections.Children.Add(b);
        }
        // Quit sits under the sections, as on the Mac, so it's never more than a click away.
        var version = Text($"Beanotch {updater.Current}", 8.5, Theme.Faint, mono: true);
        var quit = IconButton(Glyphs.Power, () => Application.Current.Exit(), 10, Theme.Red, "Quit Beanotch", 22);
        footer.Children.Clear();
        var bottom = Columns(4, (version, 1), (quit, null));
        bottom.Padding = new Thickness(S(8), S(6), S(2), 0);
        bottom.BorderBrush = Theme.Brush(Theme.Stroke);
        bottom.BorderThickness = new Thickness(0, 1, 0, 0);
        footer.Children.Add(bottom);

        content.Children.Clear();
        // Tools fill the space and scroll their own lists.
        if (section == Section.Tools)
        {
            tools ??= new ToolsPage(Model);
            content.Children.Add(tools.View);
            tools.Refresh();
            return;
        }
        FrameworkElement page = section switch
        {
            Section.Appearance => Appearance(),
            Section.Pages => Pages(),
            Section.Idle => IdleSection(),
            Section.Island => Island(),
            Section.Today => Today(),
            Section.Prayer => Prayer(),
            _ => SystemSection(),
        };
        content.Children.Add(Scroll(page));
    }

    private AppSettings S0 => Model.Settings;

    private void Save(bool rebuild = false)
    {
        S0.Save();
        if (rebuild) Rebuild();
        else Refresh();
    }

    private static Border Group(params UIElement[] rows)
    {
        var stack = V(0);
        for (var i = 0; i < rows.Length; i++)
        {
            if (i > 0) stack.Children.Add(Divider());
            var wrap = new Border { Child = rows[i], Padding = new Thickness(S(11), S(8), S(11), S(8)) };
            stack.Children.Add(wrap);
        }
        return Card(stack, 0, 12);
    }

    private static StackPanel Picker(string title, string caption, UIElement control) =>
        V(7, H(6, Text(title, 11, weight: FontWeights.Medium), Text(caption, 9, Theme.Faint)), control);

    private FrameworkElement Appearance()
    {
        var themes = Cells(Enum.GetValues<ThemeMode>().Select(mode =>
            Choice(mode.ToString(), S0.Theme == mode, ThemeSwatch(mode), () => { S0.Theme = mode; Save(rebuild: true); })));

        var swatches = H(4);
        foreach (var accent in Theme.Solids.Concat(Theme.Palettes))
        {
            var on = S0.Accent == accent;
            var dot = new Border
            {
                Width = S(14), Height = S(14), CornerRadius = new CornerRadius(S(7)), Background = Theme.Brush(Theme.Primary(accent)),
                BorderBrush = Theme.Brush(on ? Theme.Ink : Ui.Ui.Transparent), BorderThickness = new Thickness(on ? 2 : 0),
            };
            swatches.Children.Add(Plain(new Grid { Width = S(22), Height = S(22), Children = { Center(dot) } },
                                        () => { S0.Accent = accent; Save(rebuild: true); }, radius: 11, tip: accent.ToString()));
        }
        // The palettes show both their colours.
        foreach (var dot in swatches.Children.OfType<Button>().Skip(Theme.Solids.Length).Select(b => ((Grid)b.Content).Children[0]).OfType<Border>()
                                    .Select((d, i) => (d, Theme.Palettes[i])))
        {
            var (border, palette) = dot;
            border.Background = new Microsoft.UI.Xaml.Media.LinearGradientBrush
            {
                StartPoint = new Windows.Foundation.Point(0, 0), EndPoint = new Windows.Foundation.Point(1, 1),
                GradientStops = { new() { Color = Theme.Primary(palette), Offset = 0 }, new() { Color = Theme.Secondary(palette), Offset = 1 } },
            };
        }
        // An element has one parent: off the first row before onto the two.
        var all = swatches.Children.ToList();
        swatches.Children.Clear();
        var solids = H(4, [.. all.Take(Theme.Solids.Length)]);
        var palettes = H(4, [.. all.Skip(Theme.Solids.Length)]);
        // Accents that follow the song, the wallpaper, or a colour of your own.
        Button Chip(AccentChoice accent, string glyph, string title)
        {
            var on = S0.Accent == accent;
            return Plain(H(5, Icon(glyph, 9, on ? Theme.Accent : Theme.Dim), Text(title, 9.5, on ? Theme.Accent : Theme.Dim, on ? FontWeights.SemiBold : FontWeights.Normal)),
                         () => { S0.Accent = accent; Save(rebuild: true); Beanotch.Island.IslandWindow.SettingsAccentChanged?.Invoke(); },
                         on ? Theme.WithAlpha(Theme.Accent, 0.14) : Theme.WithAlpha(Theme.Ink, 0.06), 11, new Thickness(S(9), S(4), S(9), S(4)));
        }
        var chips = H(6, Chip(AccentChoice.Artwork, Glyphs.Music, "From the song"), Chip(AccentChoice.Wallpaper, "\uE91B", "From the wallpaper"),
                      Chip(AccentChoice.Custom, "\uEF3C", "Custom"));
        if (S0.Accent == AccentChoice.Custom)
        {
            var picker = new ColorPicker { Color = Tint.Parse(S0.CustomAccent) ?? Theme.Accent, IsAlphaEnabled = false, IsMoreButtonVisible = false };
            var pick = PillButton("Pick", Theme.Accent, () => { });
            pick.Flyout = new Flyout { Content = picker };
            picker.ColorChanged += (_, e) => S0.CustomAccent = Tint.Hex(e.NewColor);
            pick.Flyout.Closed += (_, _) => Save(rebuild: true);
            chips.Children.Add(pick);
        }
        var tint = Picker("Accent", "Buttons, highlights and the mini player", V(6, solids, palettes, chips));

        var size = Segmented(["Compact", "Regular", "Large", "Custom"], (int)S0.Size, i => { S0.Size = (PanelSize)i; Save(rebuild: true); });
        // Custom's two sliders; the panel takes the new size the next time it opens, the pages once you let go.
        Slider Sizer(double value, double min, double max, Action<double> set)
        {
            var slider = new Slider { Minimum = min, Maximum = max, StepFrequency = 10, Value = value, Width = S(180) };
            slider.ValueChanged += (_, e) => { set(e.NewValue); S0.Save(); };
            slider.PointerCaptureLost += (_, _) => Save(rebuild: true);
            return slider;
        }
        var custom = S0.Size == PanelSize.Custom
            ? new[]
            {
                Row(null, "Width", $"{S0.CustomWidth:0} points", Sizer(S0.CustomWidth, 460, 820, v => S0.CustomWidth = v)),
                Row(null, "Height", S0.Layout == PanelLayout.Bar ? "Bar keeps its own slim height" : $"{S0.CustomHeight:0} points",
                    Sizer(S0.CustomHeight, 180, 380, v => S0.CustomHeight = v)),
            }
            : [];
        string[] fontNames = ["Segoe UI", "Be Vietnam", "Inter", "Jakarta"];
        var fonts = Cells(Enum.GetValues<AppFont>().Select(font =>
        {
            var sample = Center(new TextBlock
            {
                Text = "Aa",
                FontSize = S(17),
                FontWeight = FontWeights.SemiBold,
                FontFamily = FontFor(FontWeights.SemiBold, true, font),
                Foreground = Theme.Brush(Theme.Ink),
            });
            var face = new Grid { Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.04)), Children = { sample } };
            return Choice(fontNames[(int)font], S0.Font == font, face, () => { S0.Font = font; Save(rebuild: true); });
        }));

        var layouts = Cells(Enum.GetValues<PanelLayout>().Select(layout =>
            Choice(layout == PanelLayout.TopTabs ? "Top tabs" : layout.ToString(), S0.Layout == layout, LayoutSketch(layout),
                   () => { S0.Layout = layout; Save(rebuild: true); })));
        var shapes = Cells(Enum.GetValues<NotchShape>().Select(shape =>
            Choice(shape.ToString(), S0.Shape == shape, ShapeSketch(shape), () => { S0.Shape = shape; Save(rebuild: true); })));

        return V(8,
            Group(Picker("Theme", "The island itself always stays black", themes), tint),
            Group(Picker("Layout", "How the panel finds its pages", layouts),
                  Picker("Notch shape", "How the island meets the top of the screen", shapes)),
            Group([Row(null, "Panel size", "How big the island opens", size), .. custom,
                  Picker("Font", "Segoe UI is Windows' own; the others ship with Beanotch, as on the Mac", fonts)]));
    }

    // The layout in miniature: where the menu sits, and the page.
    private static Grid LayoutSketch(PanelLayout layout)
    {
        var g = new Grid { Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.04)), Padding = new Thickness(S(5)) };
        Border Block(double w, double h, HorizontalAlignment ha, VerticalAlignment va, double l = 0, double t = 0, double opacity = 0.18) => new()
        {
            Width = w, Height = h, HorizontalAlignment = ha, VerticalAlignment = va, Margin = new Thickness(l, t, 0, 0),
            CornerRadius = new CornerRadius(S(2)), Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, opacity)),
        };
        var (L, T, St, C) = (HorizontalAlignment.Left, VerticalAlignment.Top, HorizontalAlignment.Stretch, VerticalAlignment.Stretch);
        switch (layout)
        {
            case PanelLayout.Studio:
                g.Children.Add(Block(S(14), double.NaN, L, C, 0, 0, 0.3));
                g.Children.Add(new Border { Margin = new Thickness(S(18), 0, 0, 0), CornerRadius = new CornerRadius(S(2)), Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.12)) });
                break;
            case PanelLayout.Compact:
                g.Children.Add(Block(S(5), double.NaN, L, C, 0, 0, 0.3));
                g.Children.Add(new Border { Margin = new Thickness(S(9), 0, 0, 0), CornerRadius = new CornerRadius(S(2)), Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.12)) });
                break;
            case PanelLayout.TopTabs:
                for (var i = 0; i < 4; i++) g.Children.Add(Block(S(9), S(4), L, T, i * S(11), 0, i == 0 ? 0.45 : 0.25));
                g.Children.Add(new Border { Margin = new Thickness(0, S(8), 0, 0), CornerRadius = new CornerRadius(S(2)), Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.12)) });
                break;
            case PanelLayout.Classic:
                g.Children.Add(Block(S(16), S(4), L, T, 0, 0, 0.4));
                for (var i = 0; i < 3; i++) g.Children.Add(Block(S(4), S(4), HorizontalAlignment.Right, T, 0, 0, i == 0 ? 0.45 : 0.25) is var dot ? Shift(dot, i) : null);
                g.Children.Add(new Border { Margin = new Thickness(0, S(8), 0, 0), CornerRadius = new CornerRadius(S(2)), Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.12)) });
                break;
            case PanelLayout.Bar:
                g.Children.Add(Block(S(10), S(8), L, T, 0, 0, 0.45));
                g.Children.Add(Block(S(32), S(8), L, T, S(12), 0, 0.2));
                g.Children.Add(Block(S(12), S(8), L, T, S(46), 0, 0.2));
                break;
            case PanelLayout.Glance:
                for (var i = 0; i < 3; i++)
                    g.Children.Add(Block(i == 2 ? S(10) : S(17), double.NaN, L, C, i * S(19), 0, i == 0 ? 0.4 : 0.2));
                break;
            case PanelLayout.Slide:
                g.Children.Add(new Border { Margin = new Thickness(0, 0, 0, S(8)), CornerRadius = new CornerRadius(S(2)), Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.12)) });
                for (var i = 0; i < 3; i++)
                    g.Children.Add(new Border
                    {
                        Width = S(i == 0 ? 8 : 3), Height = S(3), CornerRadius = new CornerRadius(S(1.5)), HorizontalAlignment = HorizontalAlignment.Center,
                        VerticalAlignment = VerticalAlignment.Bottom, Margin = new Thickness((i - 1) * S(12), 0, 0, 0),
                        Background = Theme.Brush(i == 0 ? Theme.WithAlpha(Theme.Accent, 0.8) : Theme.WithAlpha(Theme.Ink, 0.25)),
                    });
                break;
            default:
                for (var r = 0; r < 2; r++)
                    for (var c = 0; c < 3; c++) g.Children.Add(Block(S(10), S(10), L, T, c * S(13), r * S(13), 0.22));
                break;
        }
        return g;

        static Border Shift(Border dot, int i)
        {
            dot.Margin = new Thickness(0, 0, i * S(6), 0);
            return dot;
        }
    }

    // The shape in miniature: the top of the screen, and the island hanging from it.
    private static Grid ShapeSketch(NotchShape shape)
    {
        var g = new Grid { Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.04)) };
        g.Children.Add(new Border { Height = S(2), VerticalAlignment = VerticalAlignment.Top, Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.25)) });
        var r = S(6);
        g.Children.Add(new Border
        {
            Width = S(44), Height = S(14), Background = Theme.Brush(Theme.Black),
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, shape is NotchShape.Floating or NotchShape.Pill ? S(6) : 0, 0, 0),
            CornerRadius = shape switch
            {
                NotchShape.Floating => new CornerRadius(r),
                NotchShape.Pill => new CornerRadius(S(7)),
                NotchShape.Squircle => new CornerRadius(0, 0, S(9), S(9)),
                _ => new CornerRadius(0, 0, r, r),
            },
        });
        if (shape == NotchShape.Drop)
            foreach (var side in new[] { -1, 1 })
                g.Children.Add(new Border
                {
                    Width = S(5), Height = S(5), Background = Theme.Brush(Theme.Black),
                    HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Top,
                    Margin = new Thickness(side * S(49), 0, 0, 0), CornerRadius = new CornerRadius(0, 0, side < 0 ? S(5) : 0, side > 0 ? S(5) : 0),
                });
        return g;
    }

    // A pick with a picture, like the Mac's: a small preview over its name, outlined in the accent when chosen.
    private static Button Choice(string title, bool selected, FrameworkElement preview, Action pick)
    {
        var face = new Border
        {
            Height = S(40),
            CornerRadius = new CornerRadius(S(7)),
            BorderBrush = Theme.Brush(selected ? Theme.Accent : Theme.Stroke),
            BorderThickness = new Thickness(selected ? 1.5 : 1),
            Child = preview,
        };
        if (preview is Grid grid) grid.CornerRadius = new CornerRadius(S(6));
        var label = Text(title, 9.5, selected ? Theme.Ink : Theme.Dim, selected ? FontWeights.SemiBold : FontWeights.Normal);
        label.HorizontalAlignment = HorizontalAlignment.Center;
        var b = Plain(V(5, face, label), pick, radius: 9, padding: new Thickness(S(2)));
        b.HorizontalAlignment = HorizontalAlignment.Stretch;
        return b;
    }

    private static Grid Cells(IEnumerable<UIElement> items) => Columns(6, [.. items.Select(i => ((UIElement?)i, (double?)1))]);

    // The theme in miniature: its background, with the accent bar and two lines of text on top.
    private static Grid ThemeSwatch(ThemeMode mode)
    {
        Color dark = Theme.Black, light = Theme.Rgb(0.95, 0.95, 0.94);
        var g = new Grid();
        if (mode == ThemeMode.System)
        {
            g.ColumnDefinitions.Add(new ColumnDefinition());
            g.ColumnDefinitions.Add(new ColumnDefinition());
            var left = new Border { Background = Theme.Brush(light) };
            var right = new Border { Background = Theme.Brush(dark) };
            Grid.SetColumn(right, 1);
            g.Children.Add(left);
            g.Children.Add(right);
        }
        else if (mode == ThemeMode.Glass)
        {
            g.Background = new Microsoft.UI.Xaml.Media.LinearGradientBrush
            {
                StartPoint = new Windows.Foundation.Point(0, 0),
                EndPoint = new Windows.Foundation.Point(1, 1),
                GradientStops = { new() { Color = Theme.Rgb(0.4, 0.48, 0.75), Offset = 0 }, new() { Color = Theme.Rgb(0.65, 0.43, 0.6), Offset = 1 } },
            };
        }
        else if (mode == ThemeMode.Pixel)
        {
            g.Background = Theme.Brush(Theme.PixelCard);
            g.Children.Add(new Border
            {
                Width = S(20), Height = S(11), Background = Theme.Brush(Theme.Accent),
                BorderBrush = Theme.Brush(Theme.Black), BorderThickness = new Thickness(1.5, 1.5, 2.5, 2.5),
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
                Margin = new Thickness(0, 0, S(5), S(5)),
            });
        }
        else if (mode == ThemeMode.Keycap)
        {
            g.Background = Theme.Brush(dark);
            g.Children.Add(new Border
            {
                Width = S(20), Height = S(11), CornerRadius = new CornerRadius(S(3)),
                Background = KeyFace(Theme.Accent), BorderBrush = KeyEdge(), BorderThickness = new Thickness(1, 1, 1, 2),
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
                Margin = new Thickness(0, 0, S(5), S(5)),
            });
        }
        else g.Background = Theme.Brush(mode switch { ThemeMode.Light => light, _ => dark });

        Border Line(double width, double height, Color color) => new()
        {
            Width = S(width), Height = S(height), CornerRadius = new CornerRadius(S(height / 2)), Background = Theme.Brush(color),
            HorizontalAlignment = HorizontalAlignment.Left,
        };
        var lines = V(3, Line(22, 4, Theme.Accent), Line(34, 3, Theme.Rgb(0.5, 0.5, 0.5, 0.5)), Line(28, 3, Theme.Rgb(0.5, 0.5, 0.5, 0.35)));
        lines.Margin = new Thickness(S(7), S(7), 0, 0);
        Grid.SetColumnSpan(lines, 2);
        g.Children.Add(lines);
        return g;
    }

    private FrameworkElement Pages()
    {
        var rows = new List<UIElement>();
        foreach (var tab in new[] { Tab.Home, Tab.Today, Tab.Prayer, Tab.Music, Tab.Shelf, Tab.Clipboard, Tab.Ai, Tab.Controls })
        {
            var on = !S0.HiddenTabs.Contains(tab.ToString());
            rows.Add(Row(null, Model.Title(tab), tab == Tab.Prayer ? "Also hides the prayer countdown and reminders" : "", Switch(on, v =>
            {
                if (v) S0.HiddenTabs.Remove(tab.ToString()); else S0.HiddenTabs.Add(tab.ToString());
                if (tab == Tab.Prayer) { S0.PrayerCountdown = v; S0.PrayerReminder = v ? 10 : 0; }
                Save(rebuild: true);
            })));
        }
        return V(8, Text("Pages you don't use can be switched off. Settings and Tools are always a click on the gear away.", 9.5, Theme.Faint, wrap: true), Group([.. rows]));
    }

    private FrameworkElement Island()
    {
        UIElement Toggle(string title, string caption, bool on, Action<bool> set) => Row(null, title, caption, Switch(on, v => { set(v); Save(); }));
        int[] waters = [0, 30, 45, 60, 90], stretches = [0, 30, 45, 60];
        double[] delaySeconds = [0.4, 1, 2.5];
        var hotkey = Beanotch.Island.IslandWindow.CurrentHotkey?.Invoke();
        var opening = Group(
            Toggle("Open on hover", "Otherwise a click on the island opens it", S0.OpenOnHover, v => S0.OpenOnHover = v),
            Row(null, "Close after", "How long the panel waits once the pointer leaves",
                Segmented(["Quick", "1 s", "2.5 s"], Math.Max(0, Array.FindIndex(delaySeconds, d => Math.Abs(d - S0.CloseDelay) < 0.2)),
                          i => { S0.CloseDelay = delaySeconds[i]; Save(); })),
            Row(null, "Keyboard shortcut", S0.Hotkey ? (hotkey is null ? "Taken by another app" : $"{hotkey} opens and closes the panel") : "Off",
                Switch(S0.Hotkey, v => { S0.Hotkey = v; Save(); Beanotch.Island.IslandWindow.ApplyHotkey?.Invoke(); Refresh(); })),
            Toggle("Scroll for volume", "Scroll on the closed island to turn the sound up or down", S0.ScrollVolume, v => S0.ScrollVolume = v));
        var health = Group(
            Row(null, "Drink water", "A reminder while you're at the PC",
                Segmented(["Off", "30 m", "45 m", "1 h", "90 m"], Math.Max(0, Array.IndexOf(waters, S0.WaterEvery)), i => { S0.WaterEvery = waters[i]; Save(); })),
            Row(null, "Stand up", "A stretch now and then",
                Segmented(["Off", "30 m", "45 m", "1 h"], Math.Max(0, Array.IndexOf(stretches, S0.StretchEvery)), i => { S0.StretchEvery = stretches[i]; Save(); })),
            Toggle("Eye breaks", "Every 20 minutes, look 20 feet away for 20 seconds", S0.EyeBreaks, v => S0.EyeBreaks = v));

        return V(8, opening, health,
            Group(
            Toggle("Volume", "Level when it changes", S0.VolumeHud, v => S0.VolumeHud = v),
            Toggle("Downloads", "Progress from Chrome, Edge and Firefox", S0.DownloadsInIsland, v => S0.DownloadsInIsland = v),
            Toggle("Mic and camera", "When an app starts using them", S0.PrivacyAlerts, v => S0.PrivacyAlerts = v),
            Toggle("Hide in full screen", "Games, videos and slideshows that fill the screen keep it to themselves", S0.HideInFullscreen, v => S0.HideInFullscreen = v),
            Toggle("Calls", "While the mic or camera is on: call time in the island, other alerts wait", S0.CallMode, v => S0.CallMode = v),
            Toggle("Smart copy", "Codes from messages, prices in your currency, addresses and parcels", S0.SmartCopy, v => S0.SmartCopy = v),
            Toggle("Bluetooth and battery", "Devices connecting, charging, battery low", S0.DeviceAlerts, v => S0.DeviceAlerts = v),
            Toggle("Caps Lock", "When it turns on or off", S0.KeyboardAlerts, v => S0.KeyboardAlerts = v),
            Toggle("Meetings", "Five minutes before an event", S0.MeetingAlerts, v => S0.MeetingAlerts = v),
            Toggle("Prayer countdown", "In the last hour before each prayer", S0.PrayerCountdown, v => S0.PrayerCountdown = v)));
    }

    // The closed island with nothing going on: what sits on each side, what music adds, and the pet.
    private FrameworkElement IdleSection()
    {
        IdleItem[] lefts = Enum.GetValues<IdleItem>(), rights = [.. lefts.Where(i => i != IdleItem.Pet)];
        var left = Segmented([.. lefts.Select(i => i.ToString())], Array.IndexOf(lefts, S0.NotchPet ? IdleItem.Pet : S0.IdleLeft), i =>
        {
            S0.IdleLeft = lefts[i];
            S0.NotchPet = lefts[i] == IdleItem.Pet;
            Save();
        });
        var right = Segmented([.. rights.Select(i => i.ToString())], Math.Max(0, Array.IndexOf(rights, S0.IdleRight)), i => { S0.IdleRight = rights[i]; Save(); });
        var music = Segmented(["Nothing", "Cover & beat", "Lyrics"], (int)S0.MusicShows, i => { S0.MusicShows = (MusicShows)i; Save(); });
        var rows = new List<UIElement>
        {
            Picker("Left of the island", "Nothing keeps it small", left),
            Picker("Right of the island", S0.NotchPet ? "Free, it's where the pet talks" : "", right),
            Row(null, "While music plays", "Lyrics take the most room", music),
        };
        var pet = new List<UIElement>();
        if (S0.NotchPet)
        {
            pet.Add(Picker("Pet", "Who lives in the island", Cells(Enum.GetValues<Island.PetKind>().Select(kind =>
                Choice(kind.ToString(), S0.PetKind == kind,
                       new Grid { Background = Theme.Brush(Theme.Black), Children = { Center(new Island.PetView(() => Model.PetMood.Happy, () => kind, still: true).View) } },
                       () => { S0.PetKind = kind; Save(); })))));
            var name = new TextBox { Text = S0.PetName, PlaceholderText = S0.PetKind.ToString(), FontSize = S(10), Width = S(140) };
            name.LostFocus += (_, _) => { S0.PetName = name.Text.Trim(); Save(); };
            pet.Add(Row(null, "Name", "Shown when it talks to you", name));
            var level = Model.Pet;
            pet.Add(Picker("Wears", $"Level {level.Level} · {S0.PetXp % 10}/10 to the next · focus, feed and pet it to level up",
                Cells(Enum.GetValues<PetAccessory>().Select(item =>
                {
                    var open = level.Level >= Pet.LevelFor(item);
                    var preview = new Grid { Background = Theme.Brush(Theme.Black), Opacity = open ? 1 : 0.35,
                        Children = { Center(new Island.PetView(() => Model.PetMood.Happy, () => S0.PetKind, still: true, accessory: () => item).View) } };
                    return Choice(open ? (item == PetAccessory.None ? "Nothing" : item.ToString()) : $"Level {Pet.LevelFor(item)}",
                                  S0.PetAccessory == item, preview, () => { if (open) { S0.PetAccessory = item; Save(); } });
                }))));
            pet.Add(Row(null, "Cap for prayer", "Puts it on for ten minutes at each prayer time", Switch(S0.PetPrayerCap, v => { S0.PetPrayerCap = v; Save(); })));
        }
        return pet.Count == 0 ? V(8, Group([.. rows])) : V(8, Group([.. rows]), Group([.. pet]));
    }

    private FrameworkElement Today()
    {
        var url = new TextBox { Text = S0.CalendarUrl, PlaceholderText = "https://calendar.google.com/calendar/ical/…/basic.ics", FontSize = S(10) };
        var save = PillButton("Save", Theme.Accent, () =>
        {
            S0.CalendarUrl = url.Text.Trim();
            S0.Save();
            _ = Model.RefreshDataAsync(force: true);
            Refresh();
        });
        var calendar = V(6, Text("Calendar", 11, weight: FontWeights.Medium),
                         Text("Google Calendar: Settings › your calendar › Integrate › Secret address in iCal format. Outlook: Settings › Calendar › Shared calendars › Publish › ICS.",
                              9, Theme.Faint, wrap: true),
                         Columns(6, (url, 1), (save, null)));

        string[] zones = ["Europe/London", "America/New_York", "America/Los_Angeles", "Asia/Tokyo", "Asia/Singapore", "Asia/Dubai", "Europe/Berlin", "Australia/Sydney", "Asia/Riyadh"];
        var rows = zones.Select(z => (UIElement)Row(null, z.Split('/').Last().Replace('_', ' '), z, Switch(S0.Clocks.Contains(z), v =>
        {
            if (v) S0.Clocks.Add(z); else S0.Clocks.Remove(z);
            Save();
        }))).ToArray();
        return V(8, Group(calendar), Text("World clocks", 11, weight: FontWeights.Medium), Group(rows));
    }

    private FrameworkElement Prayer()
    {
        var city = new ComboBox { ItemsSource = PrayerTimes.Cities.Select(c => c.Name).ToList(), SelectedItem = S0.City, FontSize = S(10) };
        city.SelectionChanged += (_, _) => { if (city.SelectedItem is string c && c != S0.City) { S0.City = c; Save(); } };
        var method = new ComboBox { ItemsSource = Enum.GetValues<PrayerMethod>().Select(PrayerTimes.Title).ToList(), SelectedIndex = (int)S0.Method, FontSize = S(10) };
        method.SelectionChanged += (_, _) => { if (method.SelectedIndex >= 0) { S0.Method = (PrayerMethod)method.SelectedIndex; Save(); } };
        int[] minutes = [0, 5, 10, 15];
        var reminder = Segmented(["Off", "5 min", "10 min", "15 min"], Math.Max(0, Array.IndexOf(minutes, S0.PrayerReminder)),
                                 i => { S0.PrayerReminder = minutes[i]; Save(); });
        var rows = new List<UIElement>
        {
            Row(Glyphs.Location, "Place", "Times are worked out on this PC", city),
            Row(null, "Method", "", method),
            Picker("Reminder", "Before each prayer, in the island", reminder),
            Row(null, "At prayer time", "A notice and a chime when each prayer comes", Switch(S0.PrayerAlerts, v => { S0.PrayerAlerts = v; Save(); })),
        };
        if (Quakes.InIndonesia(S0.Place))
            rows.Add(Row("\uE7BA", "Earthquakes", "From BMKG: near you, strong ones, or a tsunami risk, in red", Switch(S0.QuakeAlerts, v => { S0.QuakeAlerts = v; Save(); })));
        return V(8, Group([.. rows]));
    }

    private FrameworkElement SystemSection()
    {
        var login = Row("", "Open at sign-in", "Starts Beanotch when you sign in to Windows", Switch(Updater.OpenAtLogin, v => { Updater.OpenAtLogin = v; Refresh(); }));
        var caption = updater.Failed ? "Couldn't reach GitHub" : updater.UpdateAvailable ? $"Beanotch {updater.Latest} is out, you have {updater.Current}"
                    : updater.Latest is not null ? $"Up to date ({updater.Current})" : "Looks for a new Windows release on GitHub";
        Button action = updater.UpdateAvailable
            ? PillButton(updater.Installing ? "Installing…" : $"Install {updater.Latest}", Theme.Accent, () => { _ = updater.InstallAsync(); Refresh(); })
            : PillButton(updater.Checking ? "Checking…" : "Check now", Theme.Accent2, () => { _ = updater.CheckAsync().ContinueWith(_ => Dispatch(Refresh), TaskScheduler.Default); Refresh(); });
        var updates = Row(Glyphs.Download, "Updates", caption, action);
        var command = Row("\uE756", "Terminal command",
                          DevRuns.Installed ? "Run `beanotch run npm test` in a new terminal to follow it in the island"
                                            : "Adds `beanotch`: long builds and tests show in the island, green or red when done",
                          DevRuns.Installed ? PillButton("Remove", Theme.Dim, () => { DevRuns.Uninstall(); Refresh(); })
                                            : PillButton("Install", Theme.Accent, () => { DevRuns.Install(); Refresh(); }));
        var quit = Row(Glyphs.Power, "Quit", "Close Beanotch until you open it again", PillButton("Quit", Theme.Red, () => Application.Current.Exit()));
        return V(8, Group(login, updates, command, quit));
    }
}
