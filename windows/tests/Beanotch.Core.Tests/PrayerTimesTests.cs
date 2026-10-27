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
        Assert.Equal(["Imsak 03.59", "Fajr 04.09", "Sunrise 05.25", "Dhuhr 11.38", "Asr 14.52", "Maghrib 17.47", "Isha 18.58"], times);
    }

    [Fact]
    public void NextRollsOverToTomorrowsFajr()
    {
        var jakarta = PrayerTimes.Cities[0];
        var late = new DateTimeOffset(2026, 10, 27, 23, 0, 0, Wib);
        var next = PrayerTimes.Next(late, new DateOnly(2026, 10, 27), jakarta, PrayerMethod.Kemenag);
        Assert.Equal("Fajr", next.Name);
        Assert.Equal(28, next.Time.ToOffset(Wib).Day);
    }
}
