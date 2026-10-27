using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Beanotch.Ui;

public enum ThemeMode { System, Light, Dark }

// Segoe UI is Windows' own; the others ship with the app, as on the Mac (all under the SIL Open Font License).
public enum AppFont { System, BeVietnam, Inter, Jakarta }

public enum AccentChoice { Mint, Ocean, Sunset, Rose, Lime, Violet, Teal, Gold, Crimson, Graphite }

// The Mac app's palette, so both look like the same product. Sizes on Windows are scaled up a little (see Ui.K):
// Windows text reads larger than macOS points at the same nominal size.
public static class Theme
{
    public static bool Dark { get; private set; } = true;
    public static Color AccentColor { get; private set; } = Primary(AccentChoice.Mint);
    public static Color Accent2Color { get; private set; } = Secondary(AccentChoice.Mint);

    public static void Apply(ThemeMode mode, AccentChoice accent, bool systemIsDark)
    {
        Dark = mode switch { ThemeMode.Light => false, ThemeMode.Dark => true, _ => systemIsDark };
        AccentColor = Primary(accent);
        Accent2Color = Secondary(accent);
    }

    public static Color Rgb(double r, double g, double b, double a = 1) =>
        Color.FromArgb((byte)Math.Round(a * 255), (byte)Math.Round(r * 255), (byte)Math.Round(g * 255), (byte)Math.Round(b * 255));

    public static Color Primary(AccentChoice accent) => accent switch
    {
        AccentChoice.Mint => Rgb(0.33, 0.86, 0.68),
        AccentChoice.Ocean => Rgb(0.3, 0.62, 1.0),
        AccentChoice.Sunset => Rgb(1.0, 0.58, 0.3),
        AccentChoice.Rose => Rgb(1.0, 0.42, 0.6),
        AccentChoice.Lime => Rgb(0.62, 0.86, 0.24),
        AccentChoice.Violet => Rgb(0.6, 0.48, 1.0),
        AccentChoice.Teal => Rgb(0.2, 0.78, 0.82),
        AccentChoice.Gold => Rgb(0.95, 0.76, 0.3),
        AccentChoice.Crimson => Rgb(0.94, 0.33, 0.36),
        _ => Rgb(0.62, 0.65, 0.7),
    };

    public static Color Secondary(AccentChoice accent) => accent switch
    {
        AccentChoice.Mint => Rgb(0.6, 0.5, 1.0),
        AccentChoice.Ocean => Rgb(0.25, 0.8, 0.9),
        AccentChoice.Sunset => Rgb(0.95, 0.4, 0.55),
        AccentChoice.Rose => Rgb(0.62, 0.5, 1.0),
        AccentChoice.Lime => Rgb(0.25, 0.75, 0.7),
        AccentChoice.Violet => Rgb(0.95, 0.45, 0.75),
        AccentChoice.Teal => Rgb(0.45, 0.6, 1.0),
        AccentChoice.Gold => Rgb(1.0, 0.55, 0.35),
        AccentChoice.Crimson => Rgb(1.0, 0.62, 0.3),
        _ => Rgb(0.45, 0.7, 1.0),
    };

    public static readonly Color Good = Rgb(0.33, 0.86, 0.62);
    public static readonly Color Amber = Rgb(0.98, 0.68, 0.22);
    public static readonly Color Red = Rgb(1.0, 0.4, 0.4);
    public static readonly Color Black = Rgb(0, 0, 0);

    // White on the dark panel, near-black on the light one.
    public static Color Ink => Dark ? Rgb(1, 1, 1) : Rgb(0.08, 0.08, 0.08);
    // Charcoal with lighter cards in the dark; a warm off-white with white cards in the light.
    public static Color Background => Dark ? Rgb(0.055, 0.055, 0.063) : Rgb(0.953, 0.953, 0.945);
    public static Color Surface => Dark ? Rgb(1, 1, 1, 0.045) : Rgb(1, 1, 1);
    public static Color Stroke => Dark ? Rgb(1, 1, 1, 0.07) : Rgb(0, 0, 0, 0.07);
    public static Color Thumb => Dark ? Rgb(1, 1, 1, 0.14) : Rgb(1, 1, 1);
    public static Color Dim => WithAlpha(Ink, 0.55);
    public static Color Faint => WithAlpha(Ink, 0.4);
    public static Color Accent => AccentColor;
    public static Color Accent2 => Accent2Color;

    public static Color WithAlpha(Color c, double alpha) => Color.FromArgb((byte)Math.Round(alpha * 255), c.R, c.G, c.B);

    public static Color Level(double value) => value < 0.7 ? Good : value < 0.9 ? Amber : Red;

    public static SolidColorBrush Brush(Color c) => new(c);
}
