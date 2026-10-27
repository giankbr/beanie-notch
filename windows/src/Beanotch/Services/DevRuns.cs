using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using Microsoft.UI.Dispatching;
using Microsoft.Win32;

namespace Beanotch.Services;

// Long terminal commands in the island: `beanotch run npm run build` shows the command while it runs and turns green
// or red when it ends. The command is a small PowerShell script that posts to 127.0.0.1 here, with a token from a file
// only this user can read, so web pages can't post. As on the Mac.
public sealed class DevRuns(DispatcherQueue ui)
{
    public sealed record Run(string Id, string Name, DateTimeOffset Started);

    public const int Port = 47824;
    private readonly List<Run> running = [];
    private TcpListener? listener;

    public event Action<Notice>? Notice;
    public Run? Current => running.LastOrDefault();

    static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Beanotch");
    static string Bin => Path.Combine(Folder, "bin");
    static string TokenPath => Path.Combine(Folder, "run-token");
    public static bool Installed => File.Exists(Path.Combine(Bin, "beanotch.cmd"));

    private static string Token()
    {
        try
        {
            if (File.Exists(TokenPath) && File.ReadAllText(TokenPath).Trim() is { Length: >= 32 } saved) return saved;
            Directory.CreateDirectory(Folder);
            var fresh = Guid.NewGuid().ToString("N") + Guid.NewGuid().ToString("N");
            File.WriteAllText(TokenPath, fresh);
            return fresh;
        }
        catch (Exception) { return ""; }
    }

    public void Start()
    {
        if (listener is not null) return;
        var token = Token();
        try
        {
            listener = new TcpListener(IPAddress.Loopback, Port);
            listener.Start();
        }
        catch (Exception) { listener = null; return; }
        _ = Task.Run(async () =>
        {
            while (listener is not null)
            {
                try
                {
                    using var client = await listener.AcceptTcpClientAsync();
                    var body = await ReadAsync(client.GetStream(), token);
                    var reply = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"u8.ToArray();
                    await client.GetStream().WriteAsync(reply);
                    if (body is not null) ui.TryEnqueue(() => Handle(body));
                }
                catch (Exception) { }
            }
        });
    }

    // The request's JSON body, or null when the token doesn't match.
    private static async Task<Dictionary<string, string>?> ReadAsync(NetworkStream stream, string token)
    {
        var buffer = new byte[64 * 1024];
        var read = 0;
        int end;
        while (true)
        {
            var n = await stream.ReadAsync(buffer.AsMemory(read));
            if (n == 0) return null;
            read += n;
            end = IndexOf(buffer, read, "\r\n\r\n"u8);
            if (end >= 0 || read == buffer.Length) break;
        }
        if (end < 0) return null;
        var head = Encoding.ASCII.GetString(buffer, 0, end).Split("\r\n");
        string Header(string name) => head.Skip(1).Select(l => l.Split(':', 2)).FirstOrDefault(p => p.Length == 2 && p[0].Trim().Equals(name, StringComparison.OrdinalIgnoreCase))?[1].Trim() ?? "";
        if (Header("X-Beanotch-Token") != token || token.Length == 0) return null;
        var length = int.TryParse(Header("Content-Length"), out var l) ? Math.Min(l, buffer.Length - end - 4) : 0;
        while (read < end + 4 + length)
        {
            var n = await stream.ReadAsync(buffer.AsMemory(read, end + 4 + length - read));
            if (n == 0) break;
            read += n;
        }
        try
        {
            using var json = JsonDocument.Parse(buffer.AsMemory(end + 4, Math.Min(length, read - end - 4)));
            return json.RootElement.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.ToString());
        }
        catch (Exception) { return null; }
    }

    private static int IndexOf(byte[] data, int count, ReadOnlySpan<byte> what) => data.AsSpan(0, count).IndexOf(what);

    private void Handle(Dictionary<string, string> json)
    {
        if (!json.TryGetValue("id", out var id) || !json.TryGetValue("name", out var name)) return;
        if (json.GetValueOrDefault("state") == "start")
        {
            running.RemoveAll(r => r.Id == id);
            running.Add(new Run(id, Short(name), DateTimeOffset.Now));
            return;
        }
        var run = running.FirstOrDefault(r => r.Id == id);
        if (run is null) return;
        running.Remove(run);
        var code = json.GetValueOrDefault("code") ?? "?";
        var ok = code == "0";
        var took = Duration(DateTimeOffset.Now - run.Started);
        Notice?.Invoke(new Notice(ok ? Glyphs.Done : Glyphs.Close, ok ? Ui.Theme.Good : Ui.Theme.Red,
                                  ok ? $"Done · {took}" : $"Failed · exit {code}", run.Name, TimeSpan.FromSeconds(ok ? 5 : 10), Essential: true));
    }

    private static string Short(string command)
    {
        var words = command.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (words.Length > 0) words[0] = Path.GetFileNameWithoutExtension(words[0]);
        var text = string.Join(' ', words);
        return text.Length > 40 ? text[..39] + "…" : text;
    }

    public static string Duration(TimeSpan t) =>
        t.TotalSeconds < 60 ? $"{(int)t.TotalSeconds}s" : t.TotalHours < 1 ? $"{(int)t.TotalMinutes}m {t.Seconds}s" : $"{(int)t.TotalHours}h {t.Minutes}m";

    // MARK: The command

    private const string Script = """
        # beanotch run <command…>: shows the command in the island while it runs, and whether it worked.
        $a = @($args)
        if ($a.Count -gt 0 -and $a[0] -eq 'run') { $a = @($a | Select-Object -Skip 1) }
        if ($a.Count -eq 0) { 'usage: beanotch run <command…>'; exit 2 }
        $token = Get-Content "$env:LOCALAPPDATA\Beanotch\run-token" -ErrorAction SilentlyContinue
        $id = "$PID-$([DateTimeOffset]::Now.ToUnixTimeSeconds())"
        $name = $a -join ' '
        function Post($body) {
          try {
            Invoke-RestMethod -Uri http://127.0.0.1:47824/run -Method Post -Headers @{ 'X-Beanotch-Token' = "$token" } `
              -ContentType 'application/json' -Body ($body | ConvertTo-Json -Compress) -TimeoutSec 1 | Out-Null
          } catch {}
        }
        Post @{ id = $id; name = $name; cwd = "$PWD"; state = 'start' }
        $exe = $a[0]
        $rest = @($a | Select-Object -Skip 1)
        & $exe @rest
        $code = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } elseif ($?) { 0 } else { 1 }
        Post @{ id = $id; name = $name; state = 'end'; code = "$code" }
        exit $code
        """;

    // The script and a .cmd beside it, in %LOCALAPPDATA%\Beanotch\bin, which goes on the user's PATH.
    public static bool Install()
    {
        try
        {
            Token();
            Directory.CreateDirectory(Bin);
            File.WriteAllText(Path.Combine(Bin, "beanotch.ps1"), Script);
            File.WriteAllText(Path.Combine(Bin, "beanotch.cmd"), "@powershell -NoProfile -ExecutionPolicy Bypass -File \"%~dp0beanotch.ps1\" %*\r\n");
            using var env = Registry.CurrentUser.OpenSubKey("Environment", writable: true);
            var path = env?.GetValue("Path", "", RegistryValueOptions.DoNotExpandEnvironmentNames) as string ?? "";
            if (!path.Split(';').Contains(Bin, StringComparer.OrdinalIgnoreCase))
                env?.SetValue("Path", path.Length == 0 ? Bin : path.TrimEnd(';') + ";" + Bin, RegistryValueKind.ExpandString);
            Native.EnvironmentChanged();
            return true;
        }
        catch (Exception) { return false; }
    }

    public static void Uninstall()
    {
        try
        {
            if (Directory.Exists(Bin)) Directory.Delete(Bin, true);
            using var env = Registry.CurrentUser.OpenSubKey("Environment", writable: true);
            if (env?.GetValue("Path", "", RegistryValueOptions.DoNotExpandEnvironmentNames) is string path)
                env.SetValue("Path", string.Join(';', path.Split(';').Where(p => !p.Equals(Bin, StringComparison.OrdinalIgnoreCase))), RegistryValueKind.ExpandString);
            Native.EnvironmentChanged();
        }
        catch (Exception) { }
    }
}
