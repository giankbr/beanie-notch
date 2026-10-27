using Beanotch.Services;
using Beanotch.Ui;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Devices.Radios;
using Windows.System.Power;
using static Beanotch.Ui.Ui;

namespace Beanotch.Pages;

// Controls: system switches as tiles, brightness per screen, the battery, and one-click actions (Windows has no
// Shortcuts app, so these stand in for the Mac's Shortcuts card).
public sealed class ControlsPage(Model model) : PanelPage(model)
{
    private readonly Grid tiles = new() { ColumnSpacing = S(6) };
    private readonly StackPanel brightness = V(6);
    private readonly StackPanel battery = V(4);
    private readonly Grid actions = new() { RowSpacing = S(6), ColumnSpacing = S(6) };
    private List<Display>? displays;
    private DateTime displaysAt;
    private readonly StackPanel wifi = V(6), bluetooth = V(6);
    private bool? wifiOn, bluetoothOn;
    private string? ssid, joining, passwordFor, wifiNote, busy;
    private List<WifiNetwork> networks = [];
    private List<BluetoothItem> devices = [];
    private DateTime wirelessAt;
    private bool loading;

    protected override FrameworkElement Build()
    {
        var bright = Card(V(8, Text("Brightness", 13, weight: FontWeights.SemiBold), brightness), 12, 12);
        var power = Card(V(8, Text("Battery", 13, weight: FontWeights.SemiBold), battery), 12, 12);
        var quick = Card(V(8, Text("Quick actions", 13, weight: FontWeights.SemiBold), actions), 12, 12);
        quick.Width = S(230);
        BuildActions();
        var air = Columns(10, (Card(wifi, 12, 12), 1), (Card(bluetooth, 12, 12), 1));
        return Scroll(V(10, tiles, air, Columns(10, (V(10, bright, power), 1), (quick, null))));
    }

    public override void Refresh()
    {
        Tiles();
        Battery();
        if (DateTime.UtcNow - wirelessAt > TimeSpan.FromSeconds(20)) _ = LoadWireless();
        else Wireless();
        if (displays is null || DateTime.UtcNow - displaysAt > TimeSpan.FromSeconds(30))
        {
            brightness.Children.Clear();
            brightness.Children.Add(Text("Looking for screens…", 10, Theme.Faint));
            _ = Task.Run(Brightness.Read).ContinueWith(t => Dispatch(() =>
            {
                displays = t.IsCompletedSuccessfully ? t.Result : [];
                displaysAt = DateTime.UtcNow;
                Sliders();
            }), TaskScheduler.Default);
        }
        else Sliders();
    }

    private void Tiles()
    {
        var items = new (string Glyph, string Title, Func<bool> Get, Action<bool> Set)[]
        {
            ("", "Dark mode", () => Controls.DarkMode, v => Controls.DarkMode = v),
            ("", "Keep awake", () => Controls.KeepAwake, v => Controls.KeepAwake = v),
            (Glyphs.Mic, "Mic muted", () => Controls.MicMuted, v => Controls.MicMuted = v),
            ("", "Hide taskbar", () => Controls.TaskbarHidden, v => Controls.TaskbarHidden = v),
            ("", "Desktop icons", () => Controls.DesktopIcons, v => Controls.DesktopIcons = v),
            ("", "Hidden files", () => Controls.HiddenFiles, v => Controls.HiddenFiles = v),
        };
        tiles.Children.Clear();
        tiles.ColumnDefinitions.Clear();
        for (var i = 0; i < items.Length; i++)
        {
            var (glyph, title, get, set) = items[i];
            bool on;
            try { on = get(); } catch (Exception) { on = false; }
            var label = Text(title, 10, weight: FontWeights.SemiBold, wrap: true);
            label.MaxLines = 2;
            var body = V(4, Icon(glyph, 12, on ? Theme.Accent : Theme.Dim), label, Text(on ? "On" : "Off", 8.5, on ? Theme.Accent : Theme.Faint));
            body.Padding = new Thickness(S(8));
            var tile = Plain(body, () =>
            {
                try { set(!on); } catch (Exception) { }
                Tiles();
            }, on ? Theme.WithAlpha(Theme.Accent, 0.14) : Theme.Surface, 12);
            tile.HorizontalAlignment = HorizontalAlignment.Stretch;
            tile.BorderThickness = new Thickness(1);
            tile.BorderBrush = Theme.Brush(on ? Theme.WithAlpha(Theme.Accent, 0.6) : Theme.Stroke);
            tiles.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            Grid.SetColumn(tile, i);
            tiles.Children.Add(tile);
        }
    }

    private void Sliders()
    {
        brightness.Children.Clear();
        if (displays is null || displays.Count == 0)
        {
            brightness.Children.Add(Text("No screen here takes brightness from apps", 10, Theme.Faint));
            return;
        }
        foreach (var display in displays)
        {
            var slider = new Slider { Minimum = 0, Maximum = 100, Value = display.Level, StepFrequency = 1 };
            slider.Resources["SliderTrackValueFill"] = Theme.Brush(Theme.Accent);
            var value = Text($"{display.Level}", 9.5, Theme.Faint, mono: true);
            value.Width = S(26);
            CancellationTokenSource? pending = null;
            slider.ValueChanged += (_, e) =>
            {
                value.Text = $"{(int)e.NewValue}";
                // Settle for a moment before writing: each write is a WMI or DDC/CI round trip.
                pending?.Cancel();
                pending = new CancellationTokenSource();
                var token = pending.Token;
                var level = (int)e.NewValue;
                _ = Task.Delay(250, token).ContinueWith(_ => Brightness.Set(display, level), token, TaskContinuationOptions.OnlyOnRanToCompletion, TaskScheduler.Default);
            };
            var name = Text(display.Name, 10.5, weight: FontWeights.Medium);
            name.Width = S(130);
            brightness.Children.Add(Columns(10, (Icon(display.BuiltIn ? "" : "", 11, Theme.Dim), null), (name, null), (slider, 1), (value, null)));
        }
    }

    // Wi-Fi and Bluetooth: the radios, the networks in range and the paired devices. Scanning is slow, so it runs in
    // the background every so often and the cards draw from what it found last.
    private async Task LoadWireless(bool scan = true)
    {
        if (loading) return;
        loading = true;
        wirelessAt = DateTime.UtcNow;
        Wireless();
        var wifiRadio = await Services.Wireless.RadioFor(RadioKind.WiFi);
        var btRadio = await Services.Wireless.RadioFor(RadioKind.Bluetooth);
        wifiOn = wifiRadio is null ? null : wifiRadio.State == RadioState.On;
        bluetoothOn = btRadio is null ? null : btRadio.State == RadioState.On;
        ssid = wifiOn == true ? await Services.Wireless.ConnectedSsid() : null;
        if (scan) networks = wifiOn == true ? await Services.Wireless.Scan() : [];
        devices = bluetoothOn == true ? await Services.Wireless.Paired() : [];
        loading = false;
        Wireless();
    }

    private void Wireless()
    {
        WifiCard();
        BluetoothCard();
    }

    private static Grid Header(string glyph, string title, string caption, bool? on, Action<bool> set, Action refresh)
    {
        var texts = V(1, Text(title, 13, weight: FontWeights.SemiBold), Text(caption, 9, Theme.Faint));
        return Columns(8, (Icon(glyph, 12, on == true ? Theme.Accent : Theme.Dim), null), (texts, 1),
                       (IconButton(Glyphs.Refresh, refresh, 10, tip: "Look again", box: 22), null),
                       (on is null ? null : Switch(on.Value, set), null));
    }

    private void WifiCard()
    {
        wifi.Children.Clear();
        var caption = wifiOn is null ? "No Wi-Fi adapter" : wifiOn == false ? "Off" : ssid is null ? "Not connected" : $"Connected to {ssid}";
        wifi.Children.Add(Header("\uE701", "Wi-Fi", caption, wifiOn, v => _ = Radio(RadioKind.WiFi, v), () => _ = LoadWireless()));
        if (wifiOn != true) return;
        if (loading && networks.Count == 0) { wifi.Children.Add(Text("Looking for networks…", 10, Theme.Faint)); return; }
        if (networks.Count == 0)
        {
            wifi.Children.Add(Text("No networks found. Windows 11 lists them only while Location is on.", 9.5, Theme.Faint, wrap: true));
            wifi.Children.Add(PillButton("Location settings", Theme.Accent, () => Controls.Settings("privacy-location")));
            return;
        }
        foreach (var n in networks.Take(6))
        {
            var bars = n.Bars switch { <= 1 => "\uE872", 2 => "\uE873", 3 => "\uE874", _ => "\uE701" };
            UIElement? trailing = n.Connected
                ? PillButton("Disconnect", Theme.Dim, () => _ = Leave())
                : joining == n.Ssid ? Text("Joining…", 9, Theme.Faint) : null;
            var row = Columns(8, (Icon(bars, 11, n.Connected ? Theme.Accent : Theme.Dim), null),
                              (Text(n.Ssid, 10.5, n.Connected ? Theme.Accent : Theme.Ink, n.Connected ? FontWeights.SemiBold : FontWeights.Normal), 1),
                              (n.Secured ? Icon("\uE72E", 8.5, Theme.Faint) : null, null), (trailing, null));
            row.Padding = new Thickness(S(6), S(4), S(6), S(4));
            if (n.Connected) { wifi.Children.Add(row); continue; }
            var b = Plain(row, () => _ = Join(n), radius: 7, tip: $"Join {n.Ssid}");
            b.HorizontalAlignment = HorizontalAlignment.Stretch;
            wifi.Children.Add(b);
            if (passwordFor == n.Ssid)
            {
                var box = new PasswordBox { PlaceholderText = "Password", FontSize = S(10) };
                void Go() => _ = Join(n, box.Password);
                box.KeyDown += (_, e) => { if (e.Key == Windows.System.VirtualKey.Enter) Go(); };
                wifi.Children.Add(Columns(6, (box, 1), (PillButton("Join", Theme.Accent, Go), null)));
                box.Loaded += (_, _) => box.Focus(FocusState.Programmatic);
            }
        }
        if (wifiNote is not null) wifi.Children.Add(Text(wifiNote, 9, Theme.Red, wrap: true));
    }

    private async Task Join(WifiNetwork n, string? password = null)
    {
        joining = n.Ssid;
        wifiNote = null;
        WifiCard();
        var result = await Services.Wireless.Join(n, password);
        joining = null;
        passwordFor = result == Services.Wireless.Joined.NeedsPassword ? n.Ssid : null;
        if (result == Services.Wireless.Joined.NeedsPassword && password is not null) wifiNote = "That password didn't work";
        else if (result == Services.Wireless.Joined.Failed) wifiNote = $"Couldn't join {n.Ssid}";
        await LoadWireless();
    }

    private async Task Leave()
    {
        await Services.Wireless.Leave();
        await LoadWireless(scan: false);
    }

    private async Task Radio(RadioKind kind, bool on)
    {
        await Services.Wireless.SetRadio(kind, on);
        await Task.Delay(1500);
        await LoadWireless();
    }

    private void BluetoothCard()
    {
        bluetooth.Children.Clear();
        var connected = devices.Count(d => d.Connected);
        var caption = bluetoothOn is null ? "No Bluetooth here" : bluetoothOn == false ? "Off" : connected > 0 ? $"{connected} connected" : "Nothing connected";
        bluetooth.Children.Add(Header(Glyphs.Bluetooth, "Bluetooth", caption, bluetoothOn, v => _ = Radio(RadioKind.Bluetooth, v), () => _ = LoadWireless(scan: false)));
        if (bluetoothOn != true) return;
        if (devices.Count == 0) bluetooth.Children.Add(Text(loading ? "Looking for devices…" : "No paired devices yet", 10, Theme.Faint));
        foreach (var d in devices.Take(6))
        {
            var glyph = d.Kind switch
            {
                Windows.Devices.Bluetooth.BluetoothMajorClass.AudioVideo => "\uE7F6",
                Windows.Devices.Bluetooth.BluetoothMajorClass.Peripheral => "\uE962",
                Windows.Devices.Bluetooth.BluetoothMajorClass.Phone => "\uE8EA",
                _ => Glyphs.Bluetooth,
            };
            var key = d.Address.ToString();
            // Windows lets apps reconnect headsets and speakers; anything else goes through Windows' own settings.
            UIElement trailing = busy == key ? Text(d.Connected ? "Disconnecting…" : "Connecting…", 9, Theme.Faint)
                : d.Audio ? PillButton(d.Connected ? "Disconnect" : "Connect", d.Connected ? Theme.Dim : Theme.Accent, () => _ = Pair(d))
                : Text(d.Connected ? "Connected" : "Not connected", 9, d.Connected ? Theme.Accent : Theme.Faint);
            var row = Columns(8, (Icon(glyph, 11, d.Connected ? Theme.Accent : Theme.Dim), null),
                              (Text(d.Name, 10.5, d.Connected ? Theme.Ink : Theme.WithAlpha(Theme.Ink, 0.8), d.Connected ? FontWeights.SemiBold : FontWeights.Normal), 1),
                              (trailing, null));
            row.Padding = new Thickness(S(6), S(4), S(6), S(4));
            bluetooth.Children.Add(row);
        }
        var add = PillButton("Add a device", Theme.Accent2, () => Controls.Settings("bluetooth"), Glyphs.Add);
        add.HorizontalAlignment = HorizontalAlignment.Left;
        bluetooth.Children.Add(add);
    }

    private async Task Pair(BluetoothItem d)
    {
        busy = d.Address.ToString();
        BluetoothCard();
        var ok = d.Connected ? await Services.Wireless.Disconnect(d) : await Services.Wireless.Connect(d);
        if (!ok) Controls.Settings("bluetooth");
        await Task.Delay(3000);
        busy = null;
        await LoadWireless(scan: false);
    }

    private void Battery()
    {
        battery.Children.Clear();
        try
        {
            if (PowerManager.BatteryStatus == BatteryStatus.NotPresent)
            {
                battery.Children.Add(Text("This PC runs on mains power", 10, Theme.Faint));
                return;
            }
            var percent = PowerManager.RemainingChargePercent;
            var charging = PowerManager.PowerSupplyStatus != PowerSupplyStatus.NotPresent;
            var left = PowerManager.RemainingDischargeTime;
            var caption = charging ? "Plugged in" : left.TotalHours < 48 && left > TimeSpan.Zero ? $"{(int)left.TotalHours}h {left.Minutes}m left" : "On battery";
            battery.Children.Add(Columns(10, (Icon(charging ? Glyphs.Charging : Glyphs.Battery, 11, Theme.Dim), null),
                                         (V(1, Text("This PC", 10.5, weight: FontWeights.Medium), Text(caption, 8.5, Theme.Faint)), 1),
                                         (Text($"{percent}%", 11, Theme.Level(1 - percent / 100.0), FontWeights.SemiBold, mono: true), null)));
            battery.Children.Add(Bar(percent / 100.0, Theme.Level(1 - percent / 100.0), 4));
        }
        catch (Exception) { battery.Children.Add(Text("Battery details aren't available", 10, Theme.Faint)); }
    }

    private void BuildActions()
    {
        var items = new (string Glyph, string Title, Action Run)[]
        {
            ("", "Lock", Controls.Lock),
            ("", "Sleep", Controls.Sleep),
            (Glyphs.Screenshot, "Snip", Controls.Snip),
            (Glyphs.Delete, "Empty bin", Controls.EmptyRecycleBin),
            (Glyphs.Camera, "Camera", Controls.Camera),
            (Glyphs.Settings, "Settings", () => Controls.Settings()),
        };
        actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        actions.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        for (var i = 0; i < items.Length; i++)
        {
            if (i % 2 == 0) actions.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
            var (glyph, title, run) = items[i];
            var button = Plain(H(8, Icon(glyph, 11, Theme.Accent), Text(title, 10.5, weight: FontWeights.Medium)), run,
                               Theme.WithAlpha(Theme.Ink, 0.06), 9, new Thickness(S(10), S(8), S(10), S(8)));
            button.HorizontalAlignment = HorizontalAlignment.Stretch;
            Grid.SetRow(button, i / 2);
            Grid.SetColumn(button, i % 2);
            actions.Children.Add(button);
        }
    }
}
