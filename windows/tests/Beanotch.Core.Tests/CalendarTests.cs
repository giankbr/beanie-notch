using Beanotch.Core;
using Xunit;

public class CalendarTests
{
    static readonly TimeSpan Wib = TimeSpan.FromHours(7);

    const string Ics = """
BEGIN:VCALENDAR
BEGIN:VEVENT
UID:standup
SUMMARY:Daily standup
DTSTART;TZID=Asia/Jakarta:20261026T090000
DTEND;TZID=Asia/Jakarta:20261026T091500
RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR
EXDATE;TZID=Asia/Jakarta:20261028T090000
LOCATION:https://meet.google.com/abc-defg-hij
END:VEVENT
BEGIN:VEVENT
UID:review
SUMMARY:Design review
DTSTART:20261027T060000Z
DURATION:PT1H
DESCRIPTION:Join: https://us02web.zoom.us/j/123456789?pwd=x\nThanks
END:VEVENT
BEGIN:VEVENT
UID:gone
SUMMARY:Cancelled thing
STATUS:CANCELLED
DTSTART:20261027T080000Z
DTEND:20261027T090000Z
END:VEVENT
BEGIN:VEVENT
UID:holiday
SUMMARY:Libur
DTSTART;VALUE=DATE:20261029
DTEND;VALUE=DATE:20261030
END:VEVENT
END:VCALENDAR
""";

    [Fact]
    public void ExpandsRepeatsAndSkipsExceptions()
    {
        var from = new DateTimeOffset(2026, 10, 26, 0, 0, 0, Wib);
        var events = Calendar.Parse(Ics, from, from.AddDays(5));
        var standups = events.Where(e => e.Title == "Daily standup").Select(e => e.Start.ToOffset(Wib).Day).ToList();
        Assert.Equal([26, 27, 29, 30], standups);
        Assert.All(events.Where(e => e.Title == "Daily standup"), e => Assert.Equal("https://meet.google.com/abc-defg-hij", e.Link));
        Assert.DoesNotContain(events, e => e.Title == "Cancelled thing");
    }

    [Fact]
    public void ReadsUtcDurationsAndLinksInNotes()
    {
        var from = new DateTimeOffset(2026, 10, 27, 0, 0, 0, Wib);
        var review = Calendar.Parse(Ics, from, from.AddDays(1)).Single(e => e.Title == "Design review");
        Assert.Equal(new DateTimeOffset(2026, 10, 27, 13, 0, 0, Wib), review.Start.ToOffset(Wib));
        Assert.Equal(TimeSpan.FromHours(1), review.End - review.Start);
        Assert.Equal("https://us02web.zoom.us/j/123456789?pwd=x", review.Link);
    }

    [Fact]
    public void AllDayEventsSpanTheDay()
    {
        var from = new DateTimeOffset(2026, 10, 29, 0, 0, 0, Wib);
        var holiday = Calendar.Parse(Ics, from.AddDays(-1), from.AddDays(2)).Single(e => e.Title == "Libur");
        Assert.True(holiday.AllDay);
        Assert.Equal(TimeSpan.FromDays(1), holiday.End - holiday.Start);
    }
}
