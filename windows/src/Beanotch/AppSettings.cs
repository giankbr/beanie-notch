using System.Text.Json;
using Beanotch.Core;

namespace Beanotch;

// A small JSON file in %LOCALAPPDATA%\Beanotch, since an unpackaged app has no ApplicationData.
public sealed class AppSettings
{
    public string City { get; set; } = "Jakarta";
    public PrayerMethod Method { get; set; } = PrayerMethod.Kemenag;

    static string FilePath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Beanotch", "settings.json");

    public Place Place => PrayerTimes.Cities.FirstOrDefault(c => c.Name == City) ?? PrayerTimes.Cities[0];

    public static AppSettings Load()
    {
        try { return JsonSerializer.Deserialize<AppSettings>(File.ReadAllText(FilePath)) ?? new(); }
        catch (Exception e) when (e is IOException or JsonException or UnauthorizedAccessException) { return new(); }
    }

    public void Save()
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FilePath)!);
            File.WriteAllText(FilePath, JsonSerializer.Serialize(this));
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}
