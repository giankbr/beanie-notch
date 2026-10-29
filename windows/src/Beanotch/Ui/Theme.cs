using Microsoft.UI.Xaml.Media;
using Windows.UI;

namespace Beanotch.Ui;

public enum ThemeMode { System, Light, Dark, Glass, Keycap, Pixel }

// Segoe UI is Windows' own; the others ship with the app, as on the Mac (all under the SIL Open Font License).
public enum AppFont { System, BeVietnam, Inter, Jakarta }

// Custom takes its width and height from two sliders in Settings.
public enum PanelSize { Compact, Regular, Large, Custom }

// As on the Mac: Drop curves out of the top edge, Seamless meets it square, Floating hangs just below it, rounded all round.
// Pill floats like Floating, rounded into a capsule; Squircle meets the top edge with deep, smooth corners.
public enum NotchShape { Drop, Seamless, Floating, Pill, Squircle }

// How the open panel finds its pages, as on the Mac: a labelled side menu, a rail of icons, tabs along the top, a row
// of round buttons, a grid of tiles to pick from, no menu at all with the pages swiped sideways, or one page of cards.
public enum PanelLayout { Studio, Compact, TopTabs, Classic, Launcher, Slide, Glance, Bar }

// What sits on one side of the closed island when nothing's going on. The pet only lives on the left; Auto picks what
// matters right now.
public enum IdleItem { Nothing, Auto, Pet, Time, Date, Weather, Battery, Event, Prayer }

// What the closed island shows while music plays: nothing, the cover and a beat, or the line being sung.
public enum MusicShows { Off, Beat, Lyrics }

// One colour each; then palettes drawn as a two-colour gradient; then accents that follow the song's cover, the
// wallpaper, or a colour of your own, as on the Mac.
public enum AccentChoice
{
    Mint, Ocean, Sunset, Rose, Lime, Violet, Teal, Gold, Crimson, Graphite,
    Aurora, Dusk, Matcha, Sakura, Kopi, Batik, Neon, Mono,
    Artwork, Wallpaper, Custom,
}

// The Mac app's palette, so both look like the same product. Sizes on Windows are scaled up a little (see Ui.K):
// Windows text reads larger than macOS points at the same nominal size.
public static class Theme
{
    public static bool Dark { get; private set; } = true;
    public static Color AccentColor { get; private set; } = Primary(AccentChoice.Mint);
    public static Color Accent2Color { get; private set; } = Secondary(AccentChoice.Mint);

    public static ThemeMode Mode { get; private set; } = ThemeMode.Dark;
    // Buttons, switches and cards drawn as raised keys, like the landing page's.
    public static bool Keycap => Mode == ThemeMode.Keycap;
    // 8-bit, like the notch pet: square boxes with a dark outline and a hard bevel, and a pixel font for titles.
    public static bool Pixel => Mode == ThemeMode.Pixel;
    public static readonly Color PixelCard = Rgb(0.102, 0.102, 0.141);
    public static readonly Color PixelEdge = Rgb(0.227, 0.227, 0.322);
    public static readonly Color PixelWell = Rgb(0.059, 0.059, 0.086);

    public static readonly AccentChoice[] Solids =
        [AccentChoice.Mint, AccentChoice.Ocean, AccentChoice.Sunset, AccentChoice.Rose, AccentChoice.Lime, AccentChoice.Violet,
         AccentChoice.Teal, AccentChoice.Gold, AccentChoice.Crimson, AccentChoice.Graphite];
    public static readonly AccentChoice[] Palettes =
        [AccentChoice.Aurora, AccentChoice.Dusk, AccentChoice.Matcha, AccentChoice.Sakura, AccentChoice.Kopi, AccentChoice.Batik,
         AccentChoice.Neon, AccentChoice.Mono];

    // A palette accent is drawn as a gradient from the one colour to the other where there's room for it.
    public static bool Gradient { get; private set; }

    // `own` is the colour the cover, the wallpaper or the picker gave, for the accents that follow them.
    public static void Apply(ThemeMode mode, AccentChoice accent, bool systemIsDark, Color? own = null)
    {
        Mode = mode;
        Dark = mode switch { ThemeMode.Light => false, ThemeMode.System => systemIsDark, _ => true };
        if (own is { } c && accent is AccentChoice.Artwork or AccentChoice.Wallpaper or AccentChoice.Custom)
            (AccentColor, Accent2Color) = (c, Services.Tint.Turned(c));
        // White on white would vanish: Mono turns to graphite in the light theme.
        else if (accent == AccentChoice.Mono && !Dark)
            (AccentColor, Accent2Color) = (Rgb(0.22, 0.22, 0.25), Rgb(0.45, 0.45, 0.5));
        else
            (AccentColor, Accent2Color) = (Primary(accent), Secondary(accent));
        Gradient = Palettes.Contains(accent);
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
        AccentChoice.Graphite => Rgb(0.62, 0.65, 0.7),
        AccentChoice.Aurora => Rgb(0.2, 0.85, 0.78),
        AccentChoice.Dusk => Rgb(1.0, 0.56, 0.26),
        AccentChoice.Matcha => Rgb(0.55, 0.78, 0.38),
        AccentChoice.Sakura => Rgb(1.0, 0.7, 0.79),
        AccentChoice.Kopi => Rgb(0.8, 0.6, 0.43),
        AccentChoice.Batik => Rgb(0.36, 0.42, 0.9),
        AccentChoice.Neon => Rgb(0.62, 1.0, 0.27),
        AccentChoice.Mono => Rgb(0.9, 0.9, 0.92),
        // The dynamic ones stand in with mint until their colour is known.
        _ => Rgb(0.33, 0.86, 0.68),
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
        AccentChoice.Graphite => Rgb(0.45, 0.7, 1.0),
        AccentChoice.Aurora => Rgb(0.58, 0.42, 1.0),
        AccentChoice.Dusk => Rgb(1.0, 0.36, 0.6),
        AccentChoice.Matcha => Rgb(0.86, 0.84, 0.62),
        AccentChoice.Sakura => Rgb(0.93, 0.42, 0.58),
        AccentChoice.Kopi => Rgb(0.93, 0.74, 0.46),
        AccentChoice.Batik => Rgb(0.93, 0.73, 0.3),
        AccentChoice.Neon => Rgb(0.25, 1.0, 0.72),
        AccentChoice.Mono => Rgb(0.58, 0.58, 0.62),
        _ => Rgb(0.6, 0.5, 1.0),
    };

    public static readonly Color Good = Rgb(0.33, 0.86, 0.62);
    public static readonly Color Amber = Rgb(0.98, 0.68, 0.22);
    public static readonly Color Red = Rgb(1.0, 0.4, 0.4);
    public static readonly Color Black = Rgb(0, 0, 0);

    // White on the dark panel, near-black on the light one.
    public static Color Ink => Dark ? Rgb(1, 1, 1) : Rgb(0.08, 0.08, 0.08);
    // Black, flush with the notch, with faintly lighter cards in the dark; a warm off-white with white cards in the
    // light. Glass shows the desktop through, blurred (the window's acrylic).
    public static Color Background => Mode switch
    {
        ThemeMode.Glass => Rgb(0.09, 0.09, 0.09),
        ThemeMode.Pixel => Rgb(0.043, 0.043, 0.051),
        _ => Dark ? Black : Rgb(0.953, 0.953, 0.945),
    };
    // The open panel's fill: the background, or a dark wash over the acrylic in Glass. Anything drawn over the page
    // (flyouts, buttons' text) keeps the solid background.
    public static Color Panel => Mode == ThemeMode.Glass ? Rgb(0, 0, 0, 0.3) : Background;
    public static Color Surface => Mode switch
    {
        ThemeMode.Glass => Rgb(1, 1, 1, 0.07),
        ThemeMode.Pixel => PixelCard,
        _ => Dark ? Rgb(1, 1, 1, 0.04) : Rgb(1, 1, 1),
    };
    public static Color Stroke => Mode == ThemeMode.Glass ? Rgb(1, 1, 1, 0.1) : Dark ? Rgb(1, 1, 1, 0.07) : Rgb(0, 0, 0, 0.07);
    public static Color Thumb => Dark ? Rgb(1, 1, 1, 0.14) : Rgb(1, 1, 1);
    public static Color Dim => WithAlpha(Ink, 0.55);
    public static Color Faint => WithAlpha(Ink, 0.4);
    public static Color Accent => AccentColor;
    public static Color Accent2 => Accent2Color;

    public static Color WithAlpha(Color c, double alpha) => Color.FromArgb((byte)Math.Round(alpha * 255), c.R, c.G, c.B);

    public static Color Level(double value) => value < 0.7 ? Good : value < 0.9 ? Amber : Red;

    public static SolidColorBrush Brush(Color c) => new(c);
}
