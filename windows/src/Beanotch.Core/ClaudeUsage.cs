using System.Text.Json;

namespace Beanotch.Core;

public sealed record ModelUsage(string Model, long Tokens, double Cost);

public sealed record UsageSummary(long TokensToday, double CostToday, int RequestsToday, double CostWeek, IReadOnlyList<ModelUsage> ModelsToday)
{
    public static readonly UsageSummary Empty = new(0, 0, 0, 0, []);
}

// Claude Code's own logs under %USERPROFILE%\.claude\projects, priced at API list rates: what the same tokens would
// cost on the API, not what a subscription charges. Nothing is sent anywhere.
public static class ClaudeUsage
{
    sealed record Rate(double Input, double Output, double CacheRead);

    static readonly (string Key, Rate Rate)[] Table =
    [
        ("fable-5-1", new(10, 50, 0.25)), ("mythos-5-1", new(10, 50, 0.25)), ("fable-5", new(10, 50, 1)), ("mythos", new(10, 50, 1)),
        ("opus-5-5", new(4, 20, 0.2)), ("opus-5", new(5, 25, 0.5)), ("opus-4-8", new(5, 25, 0.5)), ("opus-4-7", new(5, 25, 0.5)),
        ("opus-4-6", new(5, 25, 0.5)), ("opus-4-5", new(5, 25, 0.5)), ("opus-4", new(15, 75, 1.5)),
        ("sonnet-5", new(2, 10, 0.2)), ("sonnet-4", new(3, 15, 0.3)),
        ("haiku-5-5", new(0.1, 0.5, 0.01)), ("haiku-4-5", new(1, 5, 0.1)),
    ];

    sealed record Record(DateTimeOffset Date, string Model, long Input, long Output, long CacheRead, long Write5m, long Write1h)
    {
        public long Tokens => Input + Output + CacheRead + Write5m + Write1h;

        public double Cost
        {
            get
            {
                var m = Model.ToLowerInvariant();
                var rate = Table.FirstOrDefault(t => m.Contains(t.Key)).Rate;
                if (rate is null) return 0;
                return (Input * rate.Input + Output * rate.Output + CacheRead * rate.CacheRead
                        + Write5m * rate.Input * 1.25 + Write1h * rate.Input * 2) / 1_000_000;
            }
        }
    }

    public static string DefaultRoot =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".claude", "projects");

    public static UsageSummary Read(string root, DateTimeOffset now)
    {
        if (!Directory.Exists(root)) return UsageSummary.Empty;
        var weekAgo = now.AddDays(-7);
        var records = new Dictionary<string, Record>();
        foreach (var file in Directory.EnumerateFiles(root, "*.jsonl", SearchOption.AllDirectories))
        {
            if (File.GetLastWriteTimeUtc(file) < weekAgo.UtcDateTime) continue;
            try
            {
                using var stream = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
                using var reader = new StreamReader(stream);
                while (reader.ReadLine() is string line) Add(line, records);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        var startOfDay = new DateTimeOffset(now.Date, now.Offset);
        var today = records.Values.Where(r => r.Date >= startOfDay).ToList();
        var models = today.GroupBy(r => Short(r.Model))
            .Select(g => new ModelUsage(g.Key, g.Sum(r => r.Tokens), g.Sum(r => r.Cost)))
            .OrderByDescending(m => m.Cost).ToList();
        return new UsageSummary(today.Sum(r => r.Tokens), today.Sum(r => r.Cost), today.Count,
                                records.Values.Where(r => r.Date >= weekAgo).Sum(r => r.Cost), models);
    }

    // A response is logged once per content block; the message and request ids make it one request.
    static void Add(string line, Dictionary<string, Record> records)
    {
        if (!line.Contains("\"usage\"", StringComparison.Ordinal)) return;
        try
        {
            using var doc = JsonDocument.Parse(line);
            var root = doc.RootElement;
            if (!root.TryGetProperty("message", out var message) || message.ValueKind != JsonValueKind.Object) return;
            if (!message.TryGetProperty("usage", out var usage) || !message.TryGetProperty("model", out var modelElement)) return;
            var model = modelElement.GetString();
            if (model is null || model == "<synthetic>") return;
            if (!root.TryGetProperty("timestamp", out var stamp) || !DateTimeOffset.TryParse(stamp.GetString(), out var date)) return;
            var key = $"{Text(message, "id") ?? Guid.NewGuid().ToString()}|{Text(root, "requestId")}";
            if (records.ContainsKey(key)) return;
            long write1h = 0;
            if (usage.TryGetProperty("cache_creation", out var creation) && creation.ValueKind == JsonValueKind.Object)
                write1h = Number(creation, "ephemeral_1h_input_tokens");
            var writeTotal = Number(usage, "cache_creation_input_tokens");
            records[key] = new Record(date, model, Number(usage, "input_tokens"), Number(usage, "output_tokens"),
                                      Number(usage, "cache_read_input_tokens"), Math.Max(0, writeTotal - write1h), write1h);
        }
        catch (JsonException) { }
    }

    static string? Text(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;

    static long Number(JsonElement e, string name) =>
        e.TryGetProperty(name, out var v) && v.ValueKind == JsonValueKind.Number ? v.GetInt64() : 0;

    // "claude-opus-5-5" → "Opus 5.5".
    public static string Short(string model)
    {
        var parts = model.Replace("claude-", "").Split('-');
        if (parts.Length == 0 || parts[0].Length == 0) return model;
        var version = string.Join('.', parts.Skip(1).TakeWhile(p => p.Length <= 2 && p.All(char.IsDigit)));
        var family = char.ToUpperInvariant(parts[0][0]) + parts[0][1..];
        return version.Length == 0 ? family : $"{family} {version}";
    }
}
