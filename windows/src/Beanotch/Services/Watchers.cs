using System.Runtime.InteropServices;
using Beanotch.Ui;
using Microsoft.UI.Dispatching;
using Microsoft.Win32;
using Windows.Devices.Bluetooth;
using Windows.Devices.Enumeration;
using Windows.System.Power;
using Windows.UI;

namespace Beanotch.Services;

// A short message in the closed island: an icon, a word or two on the left, a figure on the right, and optionally a
// level bar (volume). Essential ones show even during a call; one with a link opens it when the island is clicked.
public sealed record Notice(string Glyph, Color Color, string Left, string Right, TimeSpan Duration, double? Level = null, string? Key = null,
                            bool Essential = false, Uri? Open = null);

public static class Glyphs
{
    public const string Volume = "", Mute = "", Mic = "", Camera = "", Bluetooth = "",
        Battery = "", Charging = "", Download = "", Done = "", Keyboard = "", Screenshot = "",
        Music = "", Moon = "", Home = "", Calendar = "", Shelf = "", Clipboard = "",
        Spark = "", Controls = "", Tools = "", Settings = "", Close = "", Play = "",
        Pause = "", Next = "", Previous = "", Folder = "", OpenFile = "", Pin = "",
        Search = "", Refresh = "", Grid = "", List = "", Add = "", Delete = "",
        Compass = "", Location = "", Sun = "", Power = "", Copy = "", Clock = "", ChevronDown = "\uE70D";
}

// Everything the island reports while closed, besides music and prayer: polled cheaply on the UI thread.
public sealed partial class Watchers
{
    private readonly AppSettings settings;
    private readonly DispatcherQueue ui;
    private readonly DispatcherQueueTimer fast, slow;
    private (double Level, bool Muted)? volume;
    private bool? capsLock;
    private readonly HashSet<string> micApps = [], cameraApps = [];
    private bool bluetoothReady;
    private DeviceWatcher? bluetooth;
    private PowerSupplyStatus? supply;
    private int warnedAt = 101;
    private FileSystemWatcher? downloads, screenshots;
    private readonly Dictionary<string, (long Size, DateTime At, double Rate)> active = [];

    public event Action<Notice>? Notice;
    public event Action<string>? Screenshot;

    // A call: the mic or a camera in use for a few seconds running, by any app. Ends a few seconds after both stop.
    public DateTimeOffset? CallSince { get; private set; }
    public bool CallCamera => cameraApps.Count > 0;
    public event Action<TimeSpan>? CallEnded;
    private int activeFor, idleFor;

    // The download in progress, for the closed island: name, rate and how far along (when the size is known).
    public (string Name, double Rate)? Downloading { get; private set; }

    [LibraryImport("user32.dll")]
    private static partial short GetKeyState(int key);

    public Watchers(AppSettings settings, DispatcherQueue ui)
    {
        this.settings = settings;
        this.ui = ui;
        fast = ui.CreateTimer();
        fast.Interval = TimeSpan.FromMilliseconds(250);
        fast.Tick += (_, _) => { CheckVolume(); CheckKeys(); };
        slow = ui.CreateTimer();
        slow.Interval = TimeSpan.FromSeconds(2);
        slow.Tick += (_, _) => { CheckPrivacy(); CheckDownloads(); };
    }

    public void Start()
    {
        volume = Audio.Speaker();
        capsLock = (GetKeyState(0x14) & 1) != 0;
        CheckPrivacy(announce: false);
        fast.Start();
        slow.Start();
        StartBluetooth();
        StartPower();
        StartDownloads();
        StartScreenshots();
    }

    private void Raise(Notice notice) => Notice?.Invoke(notice);

    private void CheckVolume()
    {
        if (!settings.VolumeHud) return;
        var now = Audio.Speaker();
        if (now is not { } v || volume is not { } before) { volume = now; return; }
        if (Math.Abs(v.Level - before.Level) > 0.005 || v.Muted != before.Muted)
            Raise(new Notice(v.Muted ? Glyphs.Mute : Glyphs.Volume, Theme.Accent, v.Muted ? "Muted" : "Volume",
                             v.Muted ? "" : $"{Math.Round(v.Level * 100)}", TimeSpan.FromSeconds(1.6), v.Muted ? 0 : v.Level, "volume"));
        volume = now;
    }

    private void CheckKeys()
    {
        if (!settings.KeyboardAlerts) return;
        var caps = (GetKeyState(0x14) & 1) != 0;
        if (capsLock is bool before && caps != before)
            Raise(new Notice(Glyphs.Keyboard, caps ? Theme.Amber : Theme.Dim, "Caps Lock", caps ? "On" : "Off", TimeSpan.FromSeconds(1.6), Key: "caps"));
        capsLock = caps;
    }

    // Windows records which apps are using the mic or camera in the privacy store: an app with LastUsedTimeStop = 0
    // is using it right now. This is the same list the taskbar's privacy icon reads.
    private void CheckPrivacy(bool announce = true)
    {
        announce &= settings.PrivacyAlerts;
        Compare("microphone", micApps, Glyphs.Mic, "Mic in use", announce);
        Compare("webcam", cameraApps, Glyphs.Camera, "Camera on", announce);
        TrackCall();
    }

    private void TrackCall()
    {
        var active = settings.CallMode && (micApps.Count > 0 || cameraApps.Count > 0);
        if (active)
        {
            idleFor = 0;
            if (++activeFor >= 3 && CallSince is null) CallSince = DateTimeOffset.Now.AddSeconds(-6);
        }
        else
        {
            activeFor = 0;
            if (CallSince is { } start && ++idleFor >= 2)
            {
                CallSince = null;
                CallEnded?.Invoke(DateTimeOffset.Now - start);
            }
        }
    }

    private void Compare(string capability, HashSet<string> known, string glyph, string label, bool announce)
    {
        var now = InUse(capability);
        foreach (var app in now.Except(known))
            if (announce) Raise(new Notice(glyph, Theme.Red, label, app, TimeSpan.FromSeconds(4), Key: capability));
        known.Clear();
        known.UnionWith(now);
    }

    private static HashSet<string> InUse(string capability)
    {
        var apps = new HashSet<string>();
        try
        {
            using var root = Registry.CurrentUser.OpenSubKey($@"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\{capability}");
            if (root is null) return apps;
            void Scan(RegistryKey key, bool desktop)
            {
                foreach (var name in key.GetSubKeyNames())
                {
                    if (name == "NonPackaged") continue;
                    using var app = key.OpenSubKey(name);
                    if (app?.GetValue("LastUsedTimeStop") is long stop && stop == 0 && app.GetValue("LastUsedTimeStart") is long start && start > 0)
                        apps.Add(desktop ? Path.GetFileNameWithoutExtension(name.Replace('#', '\\')) : name.Split('_')[0].Split('.').Last());
                }
            }
            Scan(root, false);
            using var desktopApps = root.OpenSubKey("NonPackaged");
            if (desktopApps is not null) Scan(desktopApps, true);
        }
        catch (Exception) { }
        return apps;
    }

    // Replaces the Mac's AirPods card: Windows can't read AirPods' battery, but it does say when a Bluetooth device
    // connects.
    private void StartBluetooth()
    {
        try
        {
            bluetooth = DeviceInformation.CreateWatcher(BluetoothDevice.GetDeviceSelectorFromConnectionStatus(BluetoothConnectionStatus.Connected));
            bluetooth.Added += (_, device) => ui.TryEnqueue(() =>
            {
                if (bluetoothReady && settings.DeviceAlerts && device.Name.Length > 0)
                    Raise(new Notice(Glyphs.Bluetooth, Theme.Accent2, "Connected", device.Name, TimeSpan.FromSeconds(3), Key: "bluetooth"));
            });
            bluetooth.Updated += (_, _) => { };
            bluetooth.EnumerationCompleted += (_, _) => ui.TryEnqueue(() => bluetoothReady = true);
            bluetooth.Start();
        }
        catch (Exception) { }
    }

    private void StartPower()
    {
        try
        {
            supply = PowerManager.PowerSupplyStatus;
            PowerManager.PowerSupplyStatusChanged += (_, _) => ui.TryEnqueue(() =>
            {
                var now = PowerManager.PowerSupplyStatus;
                var percent = PowerManager.RemainingChargePercent;
                if (PowerManager.BatteryStatus != BatteryStatus.NotPresent && supply is not null && now != supply && settings.DeviceAlerts)
                {
                    if (now == PowerSupplyStatus.Adequate)
                        Raise(new Notice(Glyphs.Charging, Theme.Good, "Charging", $"{percent}%", TimeSpan.FromSeconds(2.5), percent / 100.0, "power"));
                    else if (now == PowerSupplyStatus.NotPresent)
                        Raise(new Notice(Glyphs.Battery, Theme.Dim, "On battery", $"{percent}%", TimeSpan.FromSeconds(2.5), percent / 100.0, "power"));
                }
                supply = now;
                if (now != PowerSupplyStatus.NotPresent) warnedAt = 101;
            });
            PowerManager.RemainingChargePercentChanged += (_, _) => ui.TryEnqueue(() =>
            {
                var percent = PowerManager.RemainingChargePercent;
                if (PowerManager.PowerSupplyStatus != PowerSupplyStatus.NotPresent || !settings.DeviceAlerts) return;
                foreach (var level in new[] { 20, 10, 5 })
                {
                    if (percent <= level && warnedAt > level)
                    {
                        warnedAt = level;
                        Raise(new Notice(Glyphs.Battery, Theme.Red, "Battery low", $"{percent}%", TimeSpan.FromSeconds(4), percent / 100.0, "power"));
                        break;
                    }
                }
            });
        }
        catch (Exception) { }
    }

    // Chrome and Edge write *.crdownload, Firefox *.part; the file's growth gives the rate, and the rename at the end
    // says it's done.
    private void StartDownloads()
    {
        var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads");
        if (!Directory.Exists(folder)) return;
        try
        {
            downloads = new FileSystemWatcher(folder) { IncludeSubdirectories = false, EnableRaisingEvents = true };
            downloads.Renamed += (_, e) =>
            {
                if (!IsPartial(e.OldFullPath) || IsPartial(e.FullPath)) return;
                ui.TryEnqueue(() =>
                {
                    active.Remove(e.OldFullPath);
                    if (settings.DownloadsInIsland)
                        Raise(new Notice(Glyphs.Done, Theme.Good, "Downloaded", Path.GetFileName(e.FullPath), TimeSpan.FromSeconds(3), Key: "download"));
                });
            };
        }
        catch (Exception) { }
    }

    private static bool IsPartial(string path) =>
        path.EndsWith(".crdownload", StringComparison.OrdinalIgnoreCase) || path.EndsWith(".part", StringComparison.OrdinalIgnoreCase);

    private void CheckDownloads()
    {
        if (downloads is null || !settings.DownloadsInIsland) { Downloading = null; return; }
        var now = DateTime.UtcNow;
        try
        {
            var files = Directory.EnumerateFiles(downloads.Path).Where(IsPartial).ToList();
            foreach (var gone in active.Keys.Except(files).ToList()) active.Remove(gone);
            foreach (var file in files)
            {
                var size = new FileInfo(file).Length;
                active[file] = active.TryGetValue(file, out var before) && now > before.At
                    ? (size, now, Math.Max(0, (size - before.Size) / (now - before.At).TotalSeconds))
                    : (size, now, 0);
            }
        }
        catch (Exception) { }
        var busiest = active.OrderByDescending(a => a.Value.Rate).FirstOrDefault();
        Downloading = busiest.Key is null ? null
            : (Path.GetFileNameWithoutExtension(busiest.Key), busiest.Value.Rate);
    }

    // Win + Shift + S and Print Screen save to Pictures\Screenshots on Windows 11.
    private void StartScreenshots()
    {
        var folder = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.MyPictures), "Screenshots");
        if (!Directory.Exists(folder)) return;
        try
        {
            screenshots = new FileSystemWatcher(folder, "*.png") { EnableRaisingEvents = true };
            screenshots.Created += (_, e) => ui.TryEnqueue(() =>
            {
                Raise(new Notice(Glyphs.Screenshot, Theme.Accent, "Screenshot", settings.ScreenshotsToShelf ? "on the Shelf" : "saved",
                                 TimeSpan.FromSeconds(2.5), Key: "screenshot"));
                if (settings.ScreenshotsToShelf) Screenshot?.Invoke(e.FullPath);
            });
        }
        catch (Exception) { }
    }
}
