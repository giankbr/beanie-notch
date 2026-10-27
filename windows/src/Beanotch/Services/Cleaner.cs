namespace Beanotch.Services;

public enum CleanKind { Temp, Browser, All }

// Temp files older than a day, and the browsers' disk caches. Files in use are skipped, so cleaning while a
// browser is open frees what it can and leaves the rest.
public sealed class Cleaner
{
    private static readonly string Local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);

    private static readonly (string Name, string Root, string[] Caches)[] Browsers =
    [
        ("Chrome", Path.Combine(Local, "Google", "Chrome", "User Data"), [Path.Combine("Cache", "Cache_Data"), "Code Cache", "GPUCache"]),
        ("Edge", Path.Combine(Local, "Microsoft", "Edge", "User Data"), [Path.Combine("Cache", "Cache_Data"), "Code Cache", "GPUCache"]),
        ("Brave", Path.Combine(Local, "BraveSoftware", "Brave-Browser", "User Data"), [Path.Combine("Cache", "Cache_Data"), "Code Cache"]),
        ("Firefox", Path.Combine(Local, "Mozilla", "Firefox", "Profiles"), ["cache2"]),
    ];

    public long TempBytes { get; private set; }
    public long BrowserBytes { get; private set; }
    public long Total => TempBytes + BrowserBytes;
    public IReadOnlyList<string> FoundBrowsers { get; private set; } = [];
    public CleanKind? Cleaning { get; private set; }
    public DateTimeOffset? LastRun { get; private set; }

    public event Action? Changed;

    public async Task ScanAsync()
    {
        var (temp, browser, found) = await Task.Run(() =>
        {
            var t = TempFiles().Sum(SizeOf);
            var names = new List<string>();
            long b = 0;
            foreach (var (name, _, _) in Browsers)
            {
                var size = BrowserFolders(name).Sum(FolderSize);
                if (size > 0) names.Add(name);
                b += size;
            }
            return (t, b, names);
        });
        TempBytes = temp;
        BrowserBytes = browser;
        FoundBrowsers = found;
        Changed?.Invoke();
    }

    public async Task CleanAsync(CleanKind kind)
    {
        if (Cleaning is not null) return;
        Cleaning = kind;
        Changed?.Invoke();
        await Task.Run(() =>
        {
            if (kind is CleanKind.Temp or CleanKind.All)
                foreach (var f in TempFiles()) TryDelete(f);
            if (kind is CleanKind.Browser or CleanKind.All)
                foreach (var (name, _, _) in Browsers)
                    foreach (var dir in BrowserFolders(name))
                        foreach (var f in SafeFiles(dir)) TryDelete(f);
        });
        Cleaning = null;
        LastRun = DateTimeOffset.Now;
        await ScanAsync();
    }

    private static IEnumerable<string> TempFiles()
    {
        var cutoff = DateTime.UtcNow.AddDays(-1);
        return SafeFiles(Path.GetTempPath()).Where(f =>
        {
            try { return File.GetLastWriteTimeUtc(f) < cutoff; }
            catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return false; }
        });
    }

    private static IEnumerable<string> BrowserFolders(string browser)
    {
        var (_, root, caches) = Browsers.First(b => b.Name == browser);
        if (!Directory.Exists(root)) yield break;
        IEnumerable<string> profiles;
        try { profiles = Directory.EnumerateDirectories(root).ToList(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { yield break; }
        foreach (var profile in profiles)
            foreach (var cache in caches)
            {
                var dir = Path.Combine(profile, cache);
                if (Directory.Exists(dir)) yield return dir;
            }
    }

    private static IEnumerable<string> SafeFiles(string dir)
    {
        var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint };
        try { return Directory.EnumerateFiles(dir, "*", options).ToList(); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return []; }
    }

    private static long FolderSize(string dir) => SafeFiles(dir).Sum(SizeOf);

    private static long SizeOf(string file)
    {
        try { return new FileInfo(file).Length; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return 0; }
    }

    private static void TryDelete(string file)
    {
        try { File.Delete(file); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { }
    }
}
