using Beanotch.Core;
using Xunit;

public class PrayerTimesTests
{
    static readonly TimeSpan Wib = TimeSpan.FromHours(7);

    // The Mac app's PrayerTimes.compute for the Jakarta city point on 27 October 2026, Kemenag RI.
    [Fact]
    public void MatchesTheMacAppForJakarta()
    {
        var jakarta = PrayerTimes.Cities.First(c => c.Name == "Jakarta");
        var times = PrayerTimes.Compute(new DateOnly(2026, 10, 27), jakarta, PrayerMethod.Kemenag)
            .Select(e => $"{e.Name} {e.Time.ToOffset(Wib):HH.mm}");
        Assert.Equal(["Imsak 03.59", "Subuh 04.09", "Terbit 05.25", "Dzuhur 11.38", "Ashar 14.52", "Maghrib 17.47", "Isya 18.58"], times);
    }

    [Fact]
    public void NextRollsOverToTomorrowsSubuh()
    {
        var jakarta = PrayerTimes.Cities[0];
        var late = new DateTimeOffset(2026, 10, 27, 23, 0, 0, Wib);
        var next = PrayerTimes.Next(late, new DateOnly(2026, 10, 27), jakarta, PrayerMethod.Kemenag);
        Assert.Equal("Subuh", next.Name);
        Assert.Equal(28, next.Time.ToOffset(Wib).Day);
    }
}
