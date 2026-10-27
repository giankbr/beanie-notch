using Beanotch.Core;
using Xunit;

public class WeatherTests
{
    [Fact]
    public void KeepsTheNextFiveHoursInThePlacesTime()
    {
        var hours = Enumerable.Range(0, 24).Select(h => $"2026-10-27T{h:00}:00").ToArray();
        var r = new OpenMeteoResponse(7 * 3600, new OpenMeteoCurrent(31, 61),
            new OpenMeteoHourly(hours, Enumerable.Range(0, 24).Select(h => 25.0 + h % 7).ToArray(), Enumerable.Repeat(3, 24).ToArray()),
            new OpenMeteoDaily([31], [25]));
        var report = Weather.Parse(r, new DateTimeOffset(2026, 10, 27, 13, 30, 0, TimeSpan.FromHours(7)));
        Assert.Equal(5, report.Hours.Count);
        Assert.Equal(14, report.Hours[0].Time.Hour);
        Assert.Equal("Rain", Weather.Describe(report.Code));
    }
}
