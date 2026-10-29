using System.Runtime.InteropServices;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;
using Windows.UI;

namespace Beanotch.Services;

// The colour of a picture, as on the Mac: the average of its most colourful pixels, evened out so it reads on black
// and on white. For the accents that follow the song's cover or the wallpaper.
public static partial class Tint
{
    public static async Task<Color?> OfAsync(IRandomAccessStream stream)
    {
        try
        {
            var decoder = await BitmapDecoder.CreateAsync(stream);
            var data = await decoder.GetPixelDataAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore,
                new BitmapTransform { ScaledWidth = 16, ScaledHeight = 16, InterpolationMode = BitmapInterpolationMode.Fant },
                ExifOrientationMode.IgnoreExifOrientation, ColorManagementMode.DoNotColorManage);
            var px = data.DetachPixelData();
            var samples = new List<(double Score, double R, double G, double B)>();
            for (var i = 0; i + 3 < px.Length; i += 4)
            {
                double b = px[i] / 255.0, g = px[i + 1] / 255.0, r = px[i + 2] / 255.0;
                double max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b));
                var saturation = max == 0 ? 0 : (max - min) / max;
                samples.Add((saturation * max, r, g, b));
            }
            var top = samples.OrderByDescending(s => s.Score).Take(samples.Count / 4).ToList();
            if (top.Count == 0) return null;
            var (h, s0, _) = Hsv(top.Average(t => t.R), top.Average(t => t.G), top.Average(t => t.B));
            return FromHsv(h, Math.Clamp(s0, 0.25, 0.7), 0.88);
        }
        catch (Exception) { return null; }
    }

    // The desktop picture's colour, from the file Windows shows (a solid colour or a slideshow has none).
    public static async Task<Color?> WallpaperAsync()
    {
        var file = WallpaperPath();
        if (file.Length == 0 || !File.Exists(file)) return null;
        try
        {
            await using var stream = File.OpenRead(file);
            return await OfAsync(stream.AsRandomAccessStream());
        }
        catch (Exception) { return null; }
    }

    // The same colour a little further round the wheel: the second colour of an accent made from one.
    public static Color Turned(Color c, double amount = 0.1)
    {
        var (h, s, v) = Hsv(c.R / 255.0, c.G / 255.0, c.B / 255.0);
        return FromHsv((h + amount) % 1, s, v);
    }

    public static Color? Parse(string hex)
    {
        hex = hex.Trim().TrimStart('#');
        if (hex.Length != 6 || !uint.TryParse(hex, System.Globalization.NumberStyles.HexNumber, null, out var v)) return null;
        return Color.FromArgb(255, (byte)(v >> 16), (byte)(v >> 8), (byte)v);
    }

    public static string Hex(Color c) => $"#{c.R:X2}{c.G:X2}{c.B:X2}";

    private static (double H, double S, double V) Hsv(double r, double g, double b)
    {
        double max = Math.Max(r, Math.Max(g, b)), min = Math.Min(r, Math.Min(g, b)), d = max - min;
        var h = d == 0 ? 0 : max == r ? (g - b) / d % 6 : max == g ? (b - r) / d + 2 : (r - g) / d + 4;
        h = (h / 6 + 1) % 1;
        return (h, max == 0 ? 0 : d / max, max);
    }

    private static Color FromHsv(double h, double s, double v)
    {
        var i = (int)Math.Floor(h * 6) % 6;
        var f = h * 6 - Math.Floor(h * 6);
        double p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
        var (r, g, b) = i switch { 0 => (v, t, p), 1 => (q, v, p), 2 => (p, v, t), 3 => (p, q, v), 4 => (t, p, v), _ => (v, p, q) };
        return Color.FromArgb(255, (byte)Math.Round(r * 255), (byte)Math.Round(g * 255), (byte)Math.Round(b * 255));
    }

    private static unsafe string WallpaperPath()
    {
        var path = stackalloc char[260];
        return SystemParametersInfo(0x73, 260, path, 0) ? new string(path).TrimEnd('\0') : ""; // SPI_GETDESKWALLPAPER
    }

    [LibraryImport("user32.dll", EntryPoint = "SystemParametersInfoW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static unsafe partial bool SystemParametersInfo(uint action, uint param, char* value, uint flags);
}
