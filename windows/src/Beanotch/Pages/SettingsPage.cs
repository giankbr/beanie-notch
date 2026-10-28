using Beanotch.Core;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.UI;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Settings, laid out like the Mac's: sections down the side, one at a time on the right.
public sealed class SettingsPage(Model model, Updater updater) : PanelPage(model)
{
    private enum Section { Appearance, Pages, Island, Today, Prayer, System }

    private readonly StackPanel sections = V(1);
    private readonly Grid content = new() { ChildrenTransitions = Arrive() };
    private readonly Grid footer = new();
    private Section section = Section.Appearance;

    protected override FrameworkElement Build()
    {
        sections.Width = S(124);
        footer.Width = S(124);
        var divider = new Border { Width = 1, Background = Theme.Brush(Theme.Stroke) };
        return Columns(12, (Rows(0, (sections, 1), (footer, null)), null), (divider, null), (content, 1));
    }

    public override void Refresh()
    {
        sections.Children.Clear();
        foreach (var s in Enum.GetValues<Section>())
        {
            var active = s == section;
            var glyph = s switch
            {
                Section.Appearance => "", Section.Pages => "", Section.Island => "",
                Section.Today => Glyphs.Calendar, Section.Prayer => Glyphs.Moon, _ => Glyphs.Settings,
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
        FrameworkElement page = section switch
        {
            Section.Appearance => Appearance(),
            Section.Pages => Pages(),
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
        foreach (var accent in Enum.GetValues<AccentChoice>())
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
        var tint = Picker("Accent", "Buttons, highlights and the mini player", swatches);

        var size = Segmented(["Compact", "Regular", "Large"], (int)S0.Size, i => { S0.Size = (PanelSize)i; Save(rebuild: true); });
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

        return V(8,
            Group(Picker("Theme", "The island itself always stays black", themes), tint),
            Group(Row(null, "Panel size", "How big the island opens", size),
                  Picker("Font", "Segoe UI is Windows' own; the others ship with Beanotch, as on the Mac", fonts)));
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
        foreach (var tab in new[] { Tab.Today, Tab.Prayer, Tab.Music, Tab.Shelf, Tab.Clipboard, Tab.Ai, Tab.Controls, Tab.Tools })
        {
            var on = !S0.HiddenTabs.Contains(tab.ToString());
            rows.Add(Row(null, Model.Title(tab), tab == Tab.Prayer ? "Also hides the prayer countdown and reminders" : "", Switch(on, v =>
            {
                if (v) S0.HiddenTabs.Remove(tab.ToString()); else S0.HiddenTabs.Add(tab.ToString());
                if (tab == Tab.Prayer) { S0.PrayerCountdown = v; S0.PrayerReminder = v ? 10 : 0; }
                Save(rebuild: true);
            })));
        }
        return V(8, Text("Pages you don't use can be switched off. Overview and Settings always stay.", 9.5, Theme.Faint, wrap: true), Group([.. rows]));
    }

    private FrameworkElement Island()
    {
        UIElement Toggle(string title, string caption, bool on, Action<bool> set) => Row(null, title, caption, Switch(on, v => { set(v); Save(); }));
        var idle = new List<UIElement>
        {
            Toggle("Time when idle", "Otherwise the notch stays empty and black", S0.IdleClock, v => S0.IdleClock = v),
            Toggle("Notch pet", "Click it, rest the pointer on it, drop files on it; it reacts to the PC", S0.NotchPet, v => { S0.NotchPet = v; Refresh(); }),
        };
        if (S0.NotchPet)
            idle.Add(Picker("Pet", "Who lives in the island", Cells(Enum.GetValues<Island.PetKind>().Select(kind =>
                Choice(kind.ToString(), S0.PetKind == kind,
                       new Grid { Background = Theme.Brush(Theme.Black), Children = { Center(new Island.PetView(() => Model.PetMood.Happy, () => kind, still: true).View) } },
                       () => { S0.PetKind = kind; Save(); Refresh(); })))));
        if (S0.NotchPet)
        {
            var name = new TextBox { Text = S0.PetName, PlaceholderText = S0.PetKind.ToString(), FontSize = S(10), Width = S(140) };
            name.LostFocus += (_, _) => { S0.PetName = name.Text.Trim(); Save(); };
            idle.Add(Row(null, "Name", "Shown when it talks to you", name));
            var pet = Model.Pet;
            idle.Add(Picker("Wears", $"Level {pet.Level} · {S0.PetXp % 10}/10 to the next · focus, feed and pet it to level up",
                Cells(Enum.GetValues<PetAccessory>().Select(item =>
                {
                    var open = pet.Level >= Pet.LevelFor(item);
                    var preview = new Grid { Background = Theme.Brush(Theme.Black), Opacity = open ? 1 : 0.35,
                        Children = { Center(new Island.PetView(() => Model.PetMood.Happy, () => S0.PetKind, still: true, accessory: () => item).View) } };
                    return Choice(open ? (item == PetAccessory.None ? "Nothing" : item.ToString()) : $"Level {Pet.LevelFor(item)}",
                                  S0.PetAccessory == item, preview, () => { if (open) { S0.PetAccessory = item; Save(); Refresh(); } });
                }))));
            idle.Add(Toggle("Cap for prayer", "Puts it on for ten minutes at each prayer time", S0.PetPrayerCap, v => S0.PetPrayerCap = v));
        }
        return V(8, Group([.. idle]),
            Group(
            Toggle("Lyrics", "The line being sung, while music plays", S0.Lyrics, v => S0.Lyrics = v),
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
