namespace Beanotch.Core;

public sealed record Place(string Name, double Lat, double Lng);

public sealed record PrayerEntry(string Name, DateTimeOffset Time, bool IsPrayer);

public enum PrayerMethod { Kemenag, Mwl, UmmAlQura, Egypt, Isna }

public static class PrayerTimes
{
    public static readonly IReadOnlyList<Place> Cities =
    [
        new("Jakarta", -6.2088, 106.8456), new("Bogor", -6.5971, 106.806), new("Depok", -6.4025, 106.7942),
        new("Tangerang", -6.1783, 106.6319), new("Bekasi", -6.2383, 106.9756), new("Bandung", -6.9175, 107.6191),
        new("Cirebon", -6.732, 108.5523), new("Semarang", -6.9667, 110.4167), new("Yogyakarta", -7.7956, 110.3695),
        new("Surakarta", -7.5755, 110.8243), new("Surabaya", -7.2575, 112.7521), new("Malang", -7.9666, 112.6326),
        new("Denpasar", -8.6705, 115.2126), new("Mataram", -8.5833, 116.1167), new("Kupang", -10.1772, 123.607),
        new("Banda Aceh", 5.5483, 95.3238), new("Medan", 3.5952, 98.6722), new("Padang", -0.9471, 100.4172),
        new("Pekanbaru", 0.5071, 101.4478), new("Batam", 1.0456, 104.0305), new("Jambi", -1.6101, 103.6131),
        new("Palembang", -2.9761, 104.7754), new("Bengkulu", -3.7928, 102.2608), new("Bandar Lampung", -5.3971, 105.2668),
        new("Pontianak", -0.0263, 109.3425), new("Banjarmasin", -3.3186, 114.5944), new("Balikpapan", -1.2379, 116.8529),
        new("Samarinda", -0.5022, 117.1536), new("Makassar", -5.1477, 119.4327), new("Palu", -0.8917, 119.8707),
        new("Kendari", -3.9985, 122.5129), new("Manado", 1.4748, 124.8421), new("Ambon", -3.6954, 128.1814),
        new("Jayapura", -2.5337, 140.7181), new("Kuala Lumpur", 3.139, 101.6869), new("Singapore", 1.3521, 103.8198),
        new("Makkah", 21.3891, 39.8579), new("Madinah", 24.5247, 39.5692),
    ];

    public static string Title(PrayerMethod method) => method switch
    {
        PrayerMethod.Kemenag => "Kemenag RI",
        PrayerMethod.Mwl => "Muslim World League",
        PrayerMethod.UmmAlQura => "Umm al-Qura",
        PrayerMethod.Egypt => "Egyptian Authority",
        _ => "ISNA",
    };

    static double FajrAngle(PrayerMethod m) => m switch
    {
        PrayerMethod.Kemenag => 20, PrayerMethod.Mwl => 18, PrayerMethod.UmmAlQura => 18.5, PrayerMethod.Egypt => 19.5, _ => 15,
    };

    // Either an angle below the horizon, or minutes after Maghrib (Umm al-Qura).
    static (double? Angle, double? Minutes) Isha(PrayerMethod m) => m switch
    {
        PrayerMethod.Kemenag => (18, null), PrayerMethod.Mwl => (17, null), PrayerMethod.UmmAlQura => (null, 90),
        PrayerMethod.Egypt => (17.5, null), _ => (15, null),
    };

    // The PrayTimes.org method, as in the Mac app: sun position from the Julian date, then the hour angle for each
    // prayer's sun altitude, computed in UTC and refined once with the first pass's times. Kemenag adds 2 minutes
    // of caution (ihtiyat).
    public static IReadOnlyList<PrayerEntry> Compute(DateOnly day, Place place, PrayerMethod method, bool hanafi = false)
    {
        int year = day.Year, m = day.Month;
        if (m <= 2) { year -= 1; m += 12; }
        double a = Math.Floor(year / 100.0), b = 2 - a + Math.Floor(a / 4);
        double jd = Math.Floor(365.25 * (year + 4716)) + Math.Floor(30.6001 * (m + 1)) + day.Day + b - 1524.5 - place.Lng / (15 * 24);
        double lat = place.Lat, rad = Math.PI / 180;

        static double Fix(double v, double r) { var x = v % r; return x < 0 ? x + r : x; }
        (double Decl, double Eqt) Sun(double t)
        {
            var dd = jd + t - 2451545.0;
            double g = Fix(357.529 + 0.98560028 * dd, 360), q = Fix(280.459 + 0.98564736 * dd, 360);
            var l = Fix(q + 1.915 * Math.Sin(g * rad) + 0.020 * Math.Sin(2 * g * rad), 360);
            var e = 23.439 - 0.00000036 * dd;
            var ra = Fix(Math.Atan2(Math.Cos(e * rad) * Math.Sin(l * rad), Math.Cos(l * rad)) / rad / 15, 24);
            return (Math.Asin(Math.Sin(e * rad) * Math.Sin(l * rad)) / rad, q / 15 - ra);
        }
        double Noon(double t) => Fix(12 - Sun(t).Eqt, 24);
        double AngleTime(double angle, double t, bool ccw)
        {
            var decl = Sun(t).Decl;
            var v = (-Math.Sin(angle * rad) - Math.Sin(decl * rad) * Math.Sin(lat * rad)) / (Math.Cos(decl * rad) * Math.Cos(lat * rad));
            var h = Math.Acos(Math.Clamp(v, -1, 1)) / rad / 15;
            return Noon(t) + (ccw ? -h : h);
        }
        double Asr(double t)
        {
            var decl = Sun(t).Decl;
            var angle = -Math.Atan(1 / ((hanafi ? 2 : 1) + Math.Tan(Math.Abs(lat - decl) * rad))) / rad;
            return AngleTime(angle, t, false);
        }
        double[] Pass(double[] t)
        {
            var maghrib = AngleTime(0.833, t[4] / 24, false);
            var (ishaAngle, ishaMinutes) = Isha(method);
            var isha = ishaMinutes is double minutes ? maghrib + minutes / 60 : AngleTime(ishaAngle ?? 17, t[5] / 24, false);
            return [AngleTime(FajrAngle(method), t[0] / 24, true), AngleTime(0.833, t[1] / 24, true), Noon(t[2] / 24), Asr(t[3] / 24), maghrib, isha];
        }

        var times = Pass(Pass([5, 6, 12, 13, 18, 18]));
        var ihtiyat = method == PrayerMethod.Kemenag ? 2.0 / 60 : 0;
        var midnight = new DateTimeOffset(day.Year, day.Month, day.Day, 0, 0, 0, TimeSpan.Zero);
        DateTimeOffset At(double hours, double extra) => midnight.AddHours(hours - place.Lng / 15 + extra);
        return
        [
            new("Imsak", At(times[0], ihtiyat - 10.0 / 60), false),
            new("Subuh", At(times[0], ihtiyat), true),
            new("Terbit", At(times[1], -ihtiyat), false),
            new("Dzuhur", At(times[2], ihtiyat), true),
            new("Ashar", At(times[3], ihtiyat), true),
            new("Maghrib", At(times[4], ihtiyat), true),
            new("Isya", At(times[5], ihtiyat), true),
        ];
    }

    // The next prayer after now, rolling over to tomorrow's Subuh after Isya.
    public static PrayerEntry Next(DateTimeOffset now, DateOnly today, Place place, PrayerMethod method, bool hanafi = false)
    {
        var upcoming = Compute(today, place, method, hanafi).FirstOrDefault(e => e.IsPrayer && e.Time > now);
        return upcoming ?? Compute(today.AddDays(1), place, method, hanafi).First(e => e.Name == "Subuh");
    }
}
