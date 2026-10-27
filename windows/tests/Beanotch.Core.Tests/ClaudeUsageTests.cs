using Beanotch.Core;
using Xunit;

public class ClaudeUsageTests
{
    [Fact]
    public void CountsEachRequestOnceAndPricesIt()
    {
        var root = Directory.CreateTempSubdirectory().FullName;
        var line = """{"timestamp":"2026-10-27T03:00:00Z","requestId":"r1","message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":1000000,"output_tokens":100000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}""";
        Directory.CreateDirectory(Path.Combine(root, "p"));
        File.WriteAllLines(Path.Combine(root, "p", "s.jsonl"), [line, line, """{"type":"other"}"""]);
        var summary = ClaudeUsage.Read(root, new DateTimeOffset(2026, 10, 27, 12, 0, 0, TimeSpan.FromHours(7)));
        Assert.Equal(1, summary.RequestsToday);
        Assert.Equal(1_100_000, summary.TokensToday);
        Assert.Equal(6.0, summary.CostToday, 6);
        Assert.Equal("Opus 5.5", summary.ModelsToday.Single().Model);
        Assert.Equal(7, summary.DailyCost.Count);
        Assert.Equal(6.0, summary.DailyCost[^1], 6);
        Assert.Equal(1, summary.RequestsLast5Hours);
    }
}
