using System.Diagnostics;
using Microsoft.Win32;

namespace Beanotch.Services;

public sealed record InstalledApp(string Name, string Version, string Publisher, long Size, string Uninstall, string? Icon, string? Location);

// Windows apps register their own uninstallers; this lists them (per-user and machine-wide, both registry views)
// and runs the chosen one. The leftovers check looks for folders named after the app in AppData.
public static class Uninstaller
{
    public static List<InstalledApp> Read()
    {
        var apps = new Dictionary<string, InstalledApp>(StringComparer.OrdinalIgnoreCase);
        foreach (var hive in new[] { Registry.CurrentUser, Registry.LocalMachine })
            foreach (var view in new[] { RegistryView.Registry64, RegistryView.Registry32 })
            {
                try
                {
                    using var root = RegistryKey.OpenBaseKey(hive == Registry.CurrentUser ? RegistryHive.CurrentUser : RegistryHive.LocalMachine, view);
                    using var list = root.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Uninstall");
                    if (list is null) continue;
                    foreach (var id in list.GetSubKeyNames())
                    {
                        using var k = list.OpenSubKey(id);
                        if (k?.GetValue("DisplayName") is not string name || name.Length == 0) continue;
                        if (k.GetValue("SystemComponent") is int system && system == 1) continue;
                        if (k.GetValue("UninstallString") is not string uninstall || uninstall.Length == 0) continue;
                        var size = k.GetValue("EstimatedSize") is int kb ? kb * 1024L : 0;
                        var icon = (k.GetValue("DisplayIcon") as string)?.Split(',')[0].Trim('"');
                        apps.TryAdd(name, new InstalledApp(name, k.GetValue("DisplayVersion") as string ?? "", k.GetValue("Publisher") as string ?? "",
                                                           size, uninstall, icon, k.GetValue("InstallLocation") as string));
                    }
                }
                catch (Exception) { }
            }
        return [.. apps.Values.OrderBy(a => a.Name, StringComparer.OrdinalIgnoreCase)];
    }

    public static List<(string Path, long Size)> Leftovers(InstalledApp app)
    {
        var found = new List<(string, long)>();
        var words = new[] { app.Name, app.Name.Split(' ')[0], app.Publisher.Split(' ').FirstOrDefault() ?? "" }
            .Where(w => w.Length >= 3).Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        var roots = new[]
        {
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs"),
        };
        foreach (var root in roots.Where(Directory.Exists))
        {
            IEnumerable<string> dirs;
            try { dirs = Directory.EnumerateDirectories(root).ToList(); }
            catch (Exception) { continue; }
            foreach (var dir in dirs)
            {
                var name = Path.GetFileName(dir);
                if (words.Any(w => name.Equals(w, StringComparison.OrdinalIgnoreCase)))
                    found.Add((dir, FolderSize(dir)));
            }
        }
        if (app.Location is { Length: > 0 } location && Directory.Exists(location) && !found.Any(f => f.Item1 == location))
            found.Insert(0, (location, FolderSize(location)));
        return found;
    }

    // Runs the app's own uninstaller (which asks for permission itself if it needs it).
    public static void Run(InstalledApp app)
    {
        try
        {
            var command = app.Uninstall.Trim();
            if (command.StartsWith('"'))
            {
                var end = command.IndexOf('"', 1);
                Process.Start(new ProcessStartInfo(command[1..end], command[(end + 1)..].Trim()) { UseShellExecute = true });
            }
            else Process.Start(new ProcessStartInfo("cmd.exe", "/c " + command) { UseShellExecute = true, WindowStyle = ProcessWindowStyle.Hidden });
        }
        catch (Exception) { }
    }

    public static void Trash(string folder)
    {
        Native.Recycle(folder);
    }

    public static long FolderSize(string dir)
    {
        try
        {
            return Directory.EnumerateFiles(dir, "*", new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint })
                .Sum(f => { try { return new FileInfo(f).Length; } catch (Exception) { return 0L; } });
        }
        catch (Exception) { return 0; }
    }
}

public sealed record LargeFile(string Path, long Size, bool Installer);

// Files of 500 MB and up in the usual places, plus installers left in Downloads.
public static class LargeFiles
{
    public static List<LargeFile> Scan()
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var found = new List<LargeFile>();
        var options = new EnumerationOptions { RecurseSubdirectories = true, IgnoreInaccessible = true, AttributesToSkip = FileAttributes.ReparsePoint | FileAttributes.System };
        foreach (var folder in new[] { "Downloads", "Desktop", "Videos", "Documents", "Music", "Pictures" })
        {
            var dir = Path.Combine(home, folder);
            if (!Directory.Exists(dir)) continue;
            try
            {
                foreach (var file in Directory.EnumerateFiles(dir, "*", options))
                {
                    long size;
                    try { size = new FileInfo(file).Length; } catch (Exception) { continue; }
                    var ext = Path.GetExtension(file).ToLowerInvariant();
                    var installer = folder == "Downloads" && ext is ".exe" or ".msi" or ".msix" or ".zip" or ".iso" && size > 20_000_000;
                    if (size >= 500_000_000 || installer) found.Add(new LargeFile(file, size, installer));
                }
            }
            catch (Exception) { }
        }
        return [.. found.OrderByDescending(f => f.Size)];
    }

    public static void Trash(string file)
    {
        Native.Recycle(file);
    }
}
