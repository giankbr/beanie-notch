using Beanotch.Core;
using Xunit;

public class LyricsTests
{
    [Fact]
    public void ParsesAndSortsStampedLines()
    {
        var lines = Lyrics.Parse("[ar:Hindia]\n[00:12.50]Kedua\n[00:05.00][00:30.00]Pertama\n");
        Assert.Equal([5.0, 12.5, 30.0], lines.Select(l => l.Time.TotalSeconds));
        Assert.Equal("Pertama", lines[0].Text);
    }

    [Fact]
    public void PicksTheLineBeingSung()
    {
        var lines = Lyrics.Parse("[00:05.00]A\n[00:10.00]B");
        Assert.Null(Lyrics.At(lines, TimeSpan.FromSeconds(2)));
        Assert.Equal("A", Lyrics.At(lines, TimeSpan.FromSeconds(7))?.Text);
        Assert.Equal("B", Lyrics.At(lines, TimeSpan.FromSeconds(60))?.Text);
    }
}
