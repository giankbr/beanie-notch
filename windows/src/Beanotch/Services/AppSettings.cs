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
    public bool ClipboardHistory { get; set; } = true;
    public bool ScreenshotsToShelf { get; set; } = true;
    public bool Lyrics { get; set; } = true;
    public bool VolumeHud { get; set; } = true;
    public bool DownloadsInIsland { get; set; } = true;
    public bool PrivacyAlerts { get; set; } = true;
    public bool DeviceAlerts { get; set; } = true;
    public bool KeyboardAlerts { get; set; } = true;
    public bool PrayerCountdown { get; set; } = true;
    // When nothing else is showing, the notch is empty and black unless this puts the time in it.
    public bool IdleClock { get; set; }
    public bool MeetingAlerts { get; set; } = true;
    public int PrayerReminder { get; set; } = 10;
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
        try { return JsonSerializer.Deserialize(File.ReadAllText(FilePath), SettingsJson.Default.AppSettings) ?? new(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new(); }
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
