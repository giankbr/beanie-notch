using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace Beanotch.Services;

// Phone and Shelf over the same Wi-Fi, with nothing to install on the phone, as on the Mac: while the QR is on
// screen, a small web server takes uploads at a one-time address, and offers what's on the Shelf for download.
// Uploads land in Downloads\Beanotch and on the Shelf. Windows asks once to let it through the firewall.
public sealed class PhoneDrop
{
    private TcpListener? listener;
    private CancellationTokenSource? stop;
    private string token = "";

    public string? Address { get; private set; }
    public string? Problem { get; private set; }
    public int Received { get; private set; }
    public bool Running => listener is not null;
    // The Shelf's files, for the phone to download.
    public Func<IReadOnlyList<string>> Offered { get; set; } = () => [];
    public event Action<string>? FileReceived;
    public event Action? Changed;

    public static string Folder => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "Beanotch");

    public void Start()
    {
        if (listener is not null) return;
        if (LocalAddress() is not { } ip)
        {
            Problem = "Connect this PC to Wi-Fi or a network first";
            Changed?.Invoke();
            return;
        }
        Problem = null;
        Received = 0;
        const string letters = "abcdefghijkmnpqrstuvwxyz23456789";
        token = new string(Enumerable.Range(0, 16).Select(_ => letters[Random.Shared.Next(letters.Length)]).ToArray());
        try
        {
            listener = new TcpListener(IPAddress.Any, 0);
            listener.Start();
        }
        catch (SocketException)
        {
            listener = null;
            Problem = "Couldn't start the receiver";
            Changed?.Invoke();
            return;
        }
        Address = $"http://{ip}:{((IPEndPoint)listener.LocalEndpoint).Port}/{token}";
        stop = new CancellationTokenSource();
        _ = AcceptAsync(listener, stop.Token);
        Changed?.Invoke();
    }

    public void Stop()
    {
        Problem = null;
        stop?.Cancel();
        listener?.Stop();
        listener = null;
        Address = null;
        Changed?.Invoke();
    }

    private async Task AcceptAsync(TcpListener server, CancellationToken cancel)
    {
        while (!cancel.IsCancellationRequested)
        {
            TcpClient client;
            try { client = await server.AcceptTcpClientAsync(cancel); }
            catch (Exception) { return; }
            _ = Task.Run(() => ServeAsync(client));
        }
    }

    // One HTTP request: the page, the Shelf's list, one Shelf file sent down, or one upload's bytes streamed to disk.
    // Just enough HTTP for a phone's browser.
    private async Task ServeAsync(TcpClient client)
    {
        using var _ = client;
        var stream = client.GetStream();
        try
        {
            var (line, headers, rest) = await ReadHeadAsync(stream);
            var parts = line.Split(' ');
            if (parts.Length < 2) { await RespondAsync(stream, 400, "Bad request"); return; }
            var target = parts[1];
            var path = target.Split('?')[0];
            var query = target.Contains('?') ? target[(target.IndexOf('?') + 1)..] : "";
            var root = "/" + token;
            if (parts[0] == "GET" && path == root) await RespondAsync(stream, 200, Page, "text/html; charset=utf-8");
            else if (parts[0] == "GET" && path == root + "/files")
            {
                var files = Offered().Where(File.Exists).Select((f, i) => new FileEntry(i, Path.GetFileName(f), new FileInfo(f).Length)).ToArray();
                await RespondAsync(stream, 200, JsonSerializer.Serialize(files, FileJson.Default.FileEntryArray), "application/json");
            }
            else if (parts[0] == "GET" && path.StartsWith(root + "/file/") && int.TryParse(path[(root.Length + 6)..], out var index))
            {
                var files = Offered().Where(File.Exists).ToList();
                if (index < 0 || index >= files.Count) await RespondAsync(stream, 404, "Not found");
                else await SendFileAsync(stream, files[index]);
            }
            else if (parts[0] == "POST" && path == root + "/upload") await ReceiveAsync(stream, headers, rest, query);
            else await RespondAsync(stream, 404, "Not found");
        }
        catch (Exception) { }
    }

    private static async Task<(string Line, Dictionary<string, string> Headers, byte[] Body)> ReadHeadAsync(NetworkStream stream)
    {
        var buffer = new MemoryStream();
        var chunk = new byte[8192];
        while (buffer.Length < 32768)
        {
            var n = await stream.ReadAsync(chunk);
            if (n == 0) break;
            buffer.Write(chunk, 0, n);
            var data = buffer.ToArray();
            var end = IndexOf(data, "\r\n\r\n"u8);
            if (end < 0) continue;
            var lines = Encoding.UTF8.GetString(data, 0, end).Split("\r\n");
            var headers = lines.Skip(1).Select(l => l.Split(':', 2)).Where(p => p.Length == 2)
                .GroupBy(p => p[0].Trim().ToLowerInvariant()).ToDictionary(g => g.Key, g => g.First()[1].Trim());
            return (lines[0], headers, data[(end + 4)..]);
        }
        throw new IOException("No request");
    }

    private static int IndexOf(byte[] data, ReadOnlySpan<byte> pattern) => data.AsSpan().IndexOf(pattern);

    private async Task ReceiveAsync(NetworkStream stream, Dictionary<string, string> headers, byte[] rest, string query)
    {
        if (!headers.TryGetValue("content-length", out var lengthText) || !long.TryParse(lengthText, out var remaining))
        {
            await RespondAsync(stream, 411, "Length required");
            return;
        }
        var raw = query.Split('&').Select(p => p.Split('=', 2)).FirstOrDefault(p => p[0] == "name") is { Length: 2 } named
            ? Uri.UnescapeDataString(named[1].Replace('+', ' ')) : "file";
        var name = string.Concat(Path.GetFileName(raw).Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '-' : c));
        Directory.CreateDirectory(Folder);
        var file = Unique(Path.Combine(Folder, name.Length == 0 ? "file" : name));
        var complete = false;
        await using (var output = File.Create(file))
        {
            var first = (int)Math.Min(rest.Length, remaining);
            await output.WriteAsync(rest.AsMemory(0, first));
            remaining -= first;
            var chunk = new byte[1 << 20];
            while (remaining > 0)
            {
                var n = await stream.ReadAsync(chunk.AsMemory(0, (int)Math.Min(chunk.Length, remaining)));
                if (n == 0) break;
                await output.WriteAsync(chunk.AsMemory(0, n));
                remaining -= n;
            }
            complete = remaining <= 0;
        }
        // Cut off half way: don't keep a broken file.
        if (!complete) { File.Delete(file); return; }
        await RespondAsync(stream, 200, "ok");
        Received++;
        FileReceived?.Invoke(file);
        Changed?.Invoke();
    }

    private static async Task SendFileAsync(NetworkStream stream, string file)
    {
        var name = Path.GetFileName(file);
        var ascii = new string(name.Select(c => c < 128 && c != '"' ? c : '_').ToArray());
        await using var input = File.OpenRead(file);
        var header = $"HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {input.Length}\r\n"
                   + $"Content-Disposition: attachment; filename=\"{ascii}\"; filename*=UTF-8''{Uri.EscapeDataString(name)}\r\nConnection: close\r\n\r\n";
        await stream.WriteAsync(Encoding.UTF8.GetBytes(header));
        await input.CopyToAsync(stream);
    }

    private static async Task RespondAsync(NetworkStream stream, int status, string body, string type = "text/plain; charset=utf-8")
    {
        var payload = Encoding.UTF8.GetBytes(body);
        var header = $"HTTP/1.1 {status} {(status == 200 ? "OK" : "Error")}\r\nContent-Type: {type}\r\nContent-Length: {payload.Length}\r\nConnection: close\r\n\r\n";
        await stream.WriteAsync(Encoding.UTF8.GetBytes(header));
        await stream.WriteAsync(payload);
    }

    private static string Unique(string path)
    {
        var candidate = path;
        string folder = Path.GetDirectoryName(path)!, stem = Path.GetFileNameWithoutExtension(path), ext = Path.GetExtension(path);
        for (var n = 2; File.Exists(candidate); n++) candidate = Path.Combine(folder, $"{stem} {n}{ext}");
        return candidate;
    }

    // The PC's IPv4 address on Wi-Fi or Ethernet: an interface that's up and has a gateway, so it's the one on the
    // network the phone shares (not a virtual adapter).
    private static string? LocalAddress() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up && n.NetworkInterfaceType is not (NetworkInterfaceType.Loopback or NetworkInterfaceType.Tunnel))
            .Select(n => n.GetIPProperties())
            .Where(p => p.GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork))
            .SelectMany(p => p.UnicastAddresses)
            .Select(a => a.Address)
            .FirstOrDefault(a => a.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(a))?.ToString();

    private const string Page = """
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>Send to Beanotch</title>
    <style>
    body{margin:0;font:16px -apple-system,system-ui,sans-serif;background:#0b0b0d;color:#fff;display:flex;min-height:100vh;align-items:center;justify-content:center}
    main{width:min(92vw,420px);text-align:center}
    h1{font-size:22px;margin:0 0 6px}p{color:#9a9aa2;margin:0 0 24px}
    label{display:block;padding:28px;border:1.5px dashed #3a3a40;border-radius:18px;cursor:pointer}
    input{display:none}#status{margin-top:18px;color:#5be0bc;min-height:1.4em}
    h2{font-size:15px;margin:28px 0 10px;text-align:left}
    #list a{display:flex;justify-content:space-between;gap:12px;padding:12px 14px;margin-bottom:6px;border-radius:12px;background:#17171b;color:#fff;text-decoration:none;text-align:left}
    #list span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}#list small{color:#9a9aa2;flex:none}
    </style></head><body><main>
    <h1>Send to Beanotch</h1><p>Photos and files go straight to your PC's Shelf.</p>
    <label>Choose files<input id="f" type="file" multiple></label>
    <div id="status"></div>
    <section id="pc" hidden><h2>On the PC's Shelf</h2><div id="list"></div></section></main>
    <script>
    const s=document.getElementById('status');
    const size=b=>b<1e6?Math.max(1,Math.round(b/1e3))+' KB':(b/1e6).toFixed(1)+' MB';
    fetch(location.pathname+'/files').then(r=>r.json()).then(files=>{
      if(!files.length)return;
      const list=document.getElementById('list');
      for(const f of files){
        const a=document.createElement('a');a.href=location.pathname+'/file/'+f.i;a.download=f.name;
        const n=document.createElement('span');n.textContent=f.name;
        const z=document.createElement('small');z.textContent=size(f.size);
        a.append(n,z);list.append(a);
      }
      document.getElementById('pc').hidden=false;
    }).catch(()=>{});
    document.getElementById('f').onchange=async e=>{
      const files=[...e.target.files];let n=0;
      for(const f of files){
        s.textContent='Sending '+f.name+' ('+(n+1)+' of '+files.length+')…';
        const r=await fetch(location.pathname+'/upload?name='+encodeURIComponent(f.name),{method:'POST',body:f}).catch(()=>null);
        if(!r||!r.ok){s.textContent='Couldn\'t send '+f.name;return}
        n++;
      }
      s.textContent=n+' file'+(n==1?'':'s')+' sent ✓';e.target.value='';
    };
    </script></body></html>
    """;
}

public sealed record FileEntry(int i, string name, long size);

[System.Text.Json.Serialization.JsonSerializable(typeof(FileEntry[]))]
internal sealed partial class FileJson : System.Text.Json.Serialization.JsonSerializerContext;
