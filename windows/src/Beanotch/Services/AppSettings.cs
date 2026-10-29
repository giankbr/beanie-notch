using System.Text.Json;
using System.Text.Json.Serialization;
using Beanotch.Core;
using Beanotch.Ui;

namespace Beanotch.Services;

// A small JSON file in %LOCALAPPDATA%\Beanotch, since an unpackaged app has no ApplicationData.
public sealed class AppSettings
{
    public string City { get; set; } = "Jakarta";
    public PrayerMethod Method { get; set; } = PrayerMethod.Kemenag;
    public ThemeMode Theme { get; set; } = ThemeMode.Dark;
    public AccentChoice Accent { get; set; } = AccentChoice.Mint;
    public AppFont Font { get; set; } = AppFont.System;
    public PanelSize Size { get; set; } = PanelSize.Regular;
    public NotchShape Shape { get; set; } = NotchShape.Drop;
    public PanelLayout Layout { get; set; } = PanelLayout.Studio;
    // Opening: on hover (else on a click), how long the panel waits once the pointer leaves, and the global shortcut.
    public bool OpenOnHover { get; set; } = true;
    public double CloseDelay { get; set; } = 0.6;
    public bool Hotkey { get; set; } = true;
    // Scrolling on the closed island sets the volume.
    public bool ScrollVolume { get; set; } = true;
    // Reminders, as on the Mac: minutes between glasses of water and between stretches (0 for never), and the 20-20-20
    // eye break. Only while you're at the PC, 8 am to 10 pm.
    public int WaterEvery { get; set; }
    public int StretchEvery { get; set; }
    public bool EyeBreaks { get; set; }
    public bool ClipboardHistory { get; set; } = true;
    public bool ScreenshotsToShelf { get; set; } = true;
    public bool Lyrics { get; set; } = true;
    public bool VolumeHud { get; set; } = true;
    public bool DownloadsInIsland { get; set; } = true;
    public bool PrivacyAlerts { get; set; } = true;
    public bool DeviceAlerts { get; set; } = true;
    public bool KeyboardAlerts { get; set; } = true;
    public bool PrayerCountdown { get; set; } = true;
    // Before 1.11, the one idle choice: the time, or an empty notch. Read once into IdleLeft and IdleRight.
    public bool IdleClock { get; set; }
    // Either side of the closed island when idle; the pet on the left is the same as NotchPet.
    public IdleItem IdleLeft { get; set; }
    public IdleItem IdleRight { get; set; }
    public MusicShows MusicShows { get; set; } = MusicShows.Beat;
    // Set once the simpler island (1.11) has been applied: compact, top tabs, Today, Shelf and Music.
    public bool SimpleIsland { get; set; }
    public bool MeetingAlerts { get; set; } = true;
    public bool CallMode { get; set; } = true;
    public bool HideInFullscreen { get; set; } = true;
    public bool SmartCopy { get; set; } = true;
    public bool QuakeAlerts { get; set; } = true;
    public string QuakeSeen { get; set; } = "";
    public bool NotchPet { get; set; }
    public Island.PetKind PetKind { get; set; } = Island.PetKind.Bean;
    // Empty for the kind's own name ("Bean").
    public string PetName { get; set; } = "";
    public PetAccessory PetAccessory { get; set; }
    public bool PetPrayerCap { get; set; } = true;
    public int PetXp { get; set; }
    public string PetFedDay { get; set; } = "";
    public string PetSeenDay { get; set; } = "";
    public int PetStrokedHour { get; set; }
    // The newest version announced in the island, so each one is announced once.
    public string AnnouncedVersion { get; set; } = "";
    // The sound while a focus stretch runs; empty for none.
    public string FocusSound { get; set; } = "";
    public string RatesDay { get; set; } = "";
    public Dictionary<string, double> RatesToday { get; set; } = [];
    public Dictionary<string, double> RatesPrevious { get; set; } = [];
    public int PrayerReminder { get; set; } = 10;
    // A notice and a chime when each prayer time comes.
    public bool PrayerAlerts { get; set; } = true;
    public string CalendarUrl { get; set; } = "";
    public List<TaskItem> Tasks { get; set; } = [];
    public List<string> Clocks { get; set; } = ["Europe/London", "America/New_York", "Asia/Tokyo"];
    public List<string> HiddenTabs { get; set; } = [];
    public int FocusPreset { get; set; }
    public List<string> Shelf { get; set; } = [];
    public List<string> Pinned { get; set; } = [];

    static string FilePath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Beanotch", "settings.json");

    [JsonIgnore]
    public Place Place => PrayerTimes.Cities.FirstOrDefault(c => c.Name == City) ?? PrayerTimes.Cities[0];

    public static AppSettings Load()
    {
        // Retro (dropped in 1.9.6) and Midnight (folded into Dark in 1.10.5) read as Dark; an unknown theme name would
        // otherwise fail the whole file.
        var fresh = !File.Exists(FilePath);
        AppSettings settings;
        try
        {
            var json = File.ReadAllText(FilePath).Replace("\"Retro\"", "\"Dark\"").Replace("\"Midnight\"", "\"Dark\"");
            settings = JsonSerializer.Deserialize(json, SettingsJson.Default.AppSettings) ?? new();
        }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { settings = new(); }
        settings.Simplify(fresh);
        return settings;
    }

    // Once, for everyone, as on the Mac: the simpler island. Top tabs, the compact panel, and Today, Shelf and Music;
    // the other pages are a switch away in Settings › Pages. Prayer stays on where it was already in use, since its
    // reminders go with the page. The old idle choice becomes the two sides, and music shows its cover and a beat.
    private void Simplify(bool fresh)
    {
        if (SimpleIsland) return;
        SimpleIsland = true;
        Size = PanelSize.Compact;
        Layout = PanelLayout.TopTabs;
        foreach (var tab in new[] { "Home", "Clipboard", "Ai", "Controls" }.Concat(fresh ? new[] { "Prayer" } : Array.Empty<string>()))
            if (!HiddenTabs.Contains(tab)) HiddenTabs.Add(tab);
        (IdleLeft, IdleRight) = NotchPet ? (IdleItem.Pet, IdleItem.Nothing) : IdleClock ? (IdleItem.Date, IdleItem.Time) : (IdleItem.Nothing, IdleItem.Nothing);
        MusicShows = MusicShows.Beat;
        Save();
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this, SettingsJson.Default.AppSettings));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}

[JsonSerializable(typeof(AppSettings))]
[JsonSourceGenerationOptions(UseStringEnumConverter = true, WriteIndented = true)]
internal sealed partial class SettingsJson : JsonSerializerContext;
