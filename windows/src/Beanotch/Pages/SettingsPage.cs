using Beanotch.Core;
using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Settings, laid out like the Mac's: sections down the side, one at a time on the right.
public sealed class SettingsPage(Model model, Updater updater) : PanelPage(model)
{
    private enum Section { Appearance, Pages, Island, Today, Prayer, System }

    private readonly StackPanel sections = V(1);
    private readonly Grid content = new();
    private Section section = Section.Appearance;

    protected override FrameworkElement Build()
    {
        sections.Width = S(124);
        var divider = new Border { Width = 1, Background = Theme.Brush(Theme.Stroke) };
        return Columns(12, (sections, null), (divider, null), (content, 1));
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
        var version = Text($"Beanotch {updater.Current}", 8.5, Theme.Faint, mono: true);
        version.Margin = new Thickness(S(8), S(8), 0, 0);
        sections.Children.Add(version);

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
        var theme = Segmented(["System", "Light", "Dark"], (int)S0.Theme, i => { S0.Theme = (ThemeMode)i; Save(rebuild: true); });
        var swatches = H(4);
        foreach (var accent in Enum.GetValues<AccentChoice>())
        {
            var on = S0.Accent == accent;
            var dot = new Border
            {
                Width = S(14), Height = S(14), CornerRadius = new CornerRadius(S(7)), Background = Theme.Brush(Theme.Primary(accent)),
                BorderBrush = Theme.Brush(on ? Theme.Ink : Ui.Ui.Transparent), BorderThickness = new Thickness(on ? 2 : 0),
            };
            var b = Plain(new Grid { Width = S(22), Height = S(22), Children = { Center(dot) } }, () => { S0.Accent = accent; Save(rebuild: true); }, radius: 11,
                          tip: accent.ToString());
            swatches.Children.Add(b);
        }
        return V(8, Group(Picker("Theme", "The island itself always stays black", theme), Picker("Accent", "Buttons, highlights and the mini player", swatches)));
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
        var shape = Segmented(["Notch", "Floating"], S0.Floating ? 1 : 0, i => { S0.Floating = i == 1; Save(); });
        return V(8, Group(Picker("Shape", "Hang from the top edge like a MacBook notch, or float just below it", shape),
                          Toggle("Time when idle", "Otherwise the notch stays empty and black", S0.IdleClock, v => S0.IdleClock = v)),
            Group(
            Toggle("Lyrics", "The line being sung, while music plays", S0.Lyrics, v => S0.Lyrics = v),
            Toggle("Volume", "Level when it changes", S0.VolumeHud, v => S0.VolumeHud = v),
            Toggle("Downloads", "Progress from Chrome, Edge and Firefox", S0.DownloadsInIsland, v => S0.DownloadsInIsland = v),
            Toggle("Mic and camera", "When an app starts using them", S0.PrivacyAlerts, v => S0.PrivacyAlerts = v),
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
        return V(8, Group(Row(Glyphs.Location, "Place", "Times are worked out on this PC", city),
                          Row(null, "Method", "", method),
                          Picker("Reminder", "Before each prayer, in the island", reminder)));
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
        var quit = Row(Glyphs.Power, "Quit", "Close Beanotch until you open it again", PillButton("Quit", Theme.Red, () => Application.Current.Exit()));
        return V(8, Group(login, updates, quit));
    }
}
