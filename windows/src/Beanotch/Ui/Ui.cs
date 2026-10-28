using Microsoft.UI.Dispatching;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Hosting;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.UI;
using Windows.UI.Text;

namespace Beanotch.Ui;

// Small builders in the spirit of the Mac app's SwiftUI views: the whole UI is written in C#, which keeps it
// buildable (and checkable) without the XAML compiler.
public static class Ui
{
    // Mac points to Windows pixels: the same nominal size reads smaller on Windows. On a small screen (a laptop at a
    // high scaling, a virtual machine's window) it shrinks, so the open panel takes about the share of the screen it
    // takes on a MacBook rather than nearly all of it.
    public static double K { get; private set; } = 1.3;

    public static void FitTo(double screenWidth) => K = Math.Clamp(1.3 * Math.Min(1, screenWidth * 0.62 / (680 * 1.3)), 0.85, 1.3);
    public static double S(double v) => Math.Round(v * K, 1);

    private static readonly FontFamily SystemText = new("Segoe UI Variable Text, Segoe UI");
    private static readonly FontFamily SystemDisplay = new("Segoe UI Variable Display, Segoe UI");
    private static readonly Dictionary<string, FontFamily> Faces = [];

    public static AppFont AppFont { get; set; } = AppFont.System;

    // A bundled font is one file per weight. Regular and Bold carry the plain family name; Medium and SemiBold carry
    // their weight in it ("Inter SemiBold"), which is how Windows tells them apart.
    public static FontFamily FontFor(FontWeight weight, bool display = false, AppFont? only = null)
    {
        var (file, family) = (only ?? AppFont) switch
        {
            AppFont.BeVietnam => ("BeVietnamPro", "Be Vietnam Pro"),
            AppFont.Inter => ("Inter", "Inter"),
            AppFont.Jakarta => ("PlusJakartaSans", "Plus Jakarta Sans"),
            _ => ("", ""),
        };
        if (file.Length == 0) return display ? SystemDisplay : SystemText;
        var (face, suffix) = weight.Weight switch
        {
            >= 700 => ("Bold", ""),
            >= 600 => ("SemiBold", " SemiBold"),
            >= 500 => ("Medium", " Medium"),
            _ => ("Regular", ""),
        };
        var key = file + face;
        if (!Faces.TryGetValue(key, out var font))
            Faces[key] = font = new FontFamily($"ms-appx:///Assets/Fonts/{file}-{face}.ttf#{family}{suffix}");
        return font;
    }
    public static readonly FontFamily Mono = new("Cascadia Mono, Consolas");
    public static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    private static readonly FontFamily PixelFont = new("ms-appx:///Assets/Fonts/Silkscreen-Regular.ttf#Silkscreen");

    public static TextBlock Text(string text, double size, Color? color = null, FontWeight? weight = null, bool mono = false,
                                 bool wrap = false, bool display = false)
    {
        // Silkscreen is wide: smaller, and only where text is big enough to stay readable.
        var pixel = Theme.Pixel && !mono && size >= 14;
        var t = new TextBlock
        {
            Text = text,
            FontSize = S(pixel ? Math.Round(size * 0.85) : size),
            FontFamily = pixel ? PixelFont : mono ? Mono : FontFor(weight ?? FontWeights.Normal, display),
            FontWeight = pixel ? FontWeights.Normal : weight ?? FontWeights.Normal,
            Foreground = Theme.Brush(color ?? Theme.Ink),
            TextTrimming = TextTrimming.CharacterEllipsis,
            TextWrapping = wrap ? TextWrapping.Wrap : TextWrapping.NoWrap,
            VerticalAlignment = VerticalAlignment.Center,
        };
        if (!wrap) t.MaxLines = 1;
        return t;
    }

    public static FontIcon Icon(string glyph, double size, Color? color = null) => new()
    {
        Glyph = glyph,
        FontFamily = Icons,
        FontSize = S(size),
        Foreground = Theme.Brush(color ?? Theme.Ink),
        VerticalAlignment = VerticalAlignment.Center,
    };

    public static StackPanel H(double spacing, params UIElement?[] children) => Stack(Orientation.Horizontal, spacing, children);
    public static StackPanel V(double spacing, params UIElement?[] children) => Stack(Orientation.Vertical, spacing, children);

    private static StackPanel Stack(Orientation o, double spacing, UIElement?[] children)
    {
        var s = new StackPanel { Orientation = o, Spacing = S(spacing) };
        foreach (var c in children) if (c is not null) s.Children.Add(c);
        return s;
    }

    // A grid row: children in columns, "*" widths stretch, null widths size to content.
    public static Grid Columns(double spacing, params (UIElement? El, double? Star)[] cols)
    {
        var g = new Grid { ColumnSpacing = S(spacing) };
        for (var i = 0; i < cols.Length; i++)
        {
            g.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = cols[i].Star is double star ? new GridLength(star, GridUnitType.Star) : GridLength.Auto,
            });
            if (cols[i].El is UIElement el)
            {
                el.SetValue(Grid.ColumnProperty, i);
                g.Children.Add(el);
            }
        }
        return g;
    }

    public static Grid Rows(double spacing, params (UIElement? El, double? Star)[] rows)
    {
        var g = new Grid { RowSpacing = S(spacing) };
        for (var i = 0; i < rows.Length; i++)
        {
            g.RowDefinitions.Add(new RowDefinition
            {
                Height = rows[i].Star is double star ? new GridLength(star, GridUnitType.Star) : GridLength.Auto,
            });
            if (rows[i].El is UIElement el)
            {
                el.SetValue(Grid.RowProperty, i);
                g.Children.Add(el);
            }
        }
        return g;
    }

    // The rounded, hairline-edged card every dashboard block sits on.
    public static Border Card(UIElement child, double padding = 10, double radius = 12) => new()
    {
        Child = child,
        Padding = new Thickness(S(padding)),
        CornerRadius = new CornerRadius(Theme.Pixel ? 0 : S(radius)),
        Background = Theme.Keycap ? Vertical(Theme.Rgb(1, 1, 1, 0.105), Theme.Rgb(1, 1, 1, 0.08)) : Theme.Brush(Theme.Surface),
        BorderBrush = Theme.Keycap ? KeyEdge() : Theme.Brush(Theme.Pixel ? Theme.PixelEdge : Theme.Stroke),
        BorderThickness = new Thickness(Theme.Pixel ? 2 : 1),
    };

    public static LinearGradientBrush Vertical(params Color[] stops)
    {
        var brush = new LinearGradientBrush { StartPoint = new Windows.Foundation.Point(0, 0), EndPoint = new Windows.Foundation.Point(0, 1) };
        for (var i = 0; i < stops.Length; i++)
            brush.GradientStops.Add(new GradientStop { Color = stops[i], Offset = stops.Length == 1 ? 0 : (double)i / (stops.Length - 1) });
        return brush;
    }

    // A key's face: lit from the top, a shade darker at the bottom. A see-through tint sits on a neutral key, worked
    // out against the panel so the face stays opaque.
    public static LinearGradientBrush KeyFace(Color fill, bool lit = false)
    {
        Color top, bottom;
        if (fill.A == 255)
        {
            top = Blend(fill, Theme.Rgb(1, 1, 1), 0.28);
            bottom = Blend(fill, Theme.Rgb(0, 0, 0), 0.12);
        }
        else
        {
            var tint = Theme.WithAlpha(fill, 1);
            top = Blend(Blend(Theme.Background, Theme.Rgb(1, 1, 1), 0.2), tint, fill.A / 255.0);
            bottom = Blend(Blend(Theme.Background, Theme.Rgb(1, 1, 1), 0.135), tint, fill.A / 255.0);
        }
        if (lit) { top = Blend(top, Theme.Rgb(1, 1, 1), 0.08); bottom = Blend(bottom, Theme.Rgb(1, 1, 1), 0.08); }
        return Vertical(top, bottom);
    }

    // The key's edge: a highlight along the top, a shadow along the thicker bottom lip.
    public static LinearGradientBrush KeyEdge() =>
        Vertical(Theme.Rgb(1, 1, 1, 0.22), Theme.Rgb(1, 1, 1, 0.04), Theme.Rgb(0, 0, 0, 0.55));

    // A pixel button's face: a solid fill as given; a see-through tint over slate, worked out to stay opaque.
    public static Color PixelFace(Color fill) =>
        fill.A == 255 ? fill : Blend(Theme.PixelEdge, Theme.WithAlpha(fill, 1), fill.A / 255.0 * 1.5);

    // The recess a key sits in: a touch lighter than the card, shaded along its top.
    public static Brush KeyWell() => Theme.Brush(Theme.Rgb(1, 1, 1, 0.055));
    public static Brush KeyWellEdge() => Vertical(Theme.Rgb(0, 0, 0, 0.5), Theme.Rgb(1, 1, 1, 0.06));

    public static Border Pill(string text, Color color, string? glyph = null, bool dot = false)
    {
        var row = H(4,
            dot ? new Border { Width = S(5), Height = S(5), CornerRadius = new CornerRadius(S(2.5)), Background = Theme.Brush(color) } : null,
            glyph is null ? null : Icon(glyph, 7.5, color),
            Text(text, 8.5, color, FontWeights.SemiBold));
        return new Border
        {
            Child = row,
            Padding = new Thickness(S(7), S(3), S(7), S(3)),
            CornerRadius = new CornerRadius(S(5)),
            Background = Theme.Brush(Theme.WithAlpha(color, 0.12)),
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    // A flat button with no system chrome: our own face, and a gentle tint on hover and press.
    public static Button Plain(UIElement content, Action onClick, Color? background = null, double radius = 7,
                               Thickness? padding = null, string? tip = null)
    {
        var fill = background ?? Colors.Transparent;
        var b = new Button
        {
            Content = content,
            Padding = padding ?? new Thickness(0),
            Background = Theme.Brush(fill),
            BorderThickness = new Thickness(0),
            CornerRadius = new CornerRadius(S(radius)),
            MinWidth = 0,
            MinHeight = 0,
            HorizontalContentAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Center,
        };
        Brush hover = Theme.Brush(Blend(fill, Theme.Ink, 0.08));
        Brush press = Theme.Brush(Blend(fill, Theme.Ink, 0.14));
        Brush edge = Theme.Brush(Colors.Transparent);
        if (Theme.Keycap && fill.A > 0)
        {
            b.Background = KeyFace(fill);
            hover = KeyFace(fill, lit: true);
            press = Theme.Brush(Blend(Theme.WithAlpha(fill, 1), Theme.Background, 1 - fill.A / 255.0));
            edge = KeyEdge();
            b.BorderBrush = edge;
            b.BorderThickness = new Thickness(1, 1, 1, 2);
        }
        else if (Theme.Pixel && fill.A > 0)
        {
            // A flat face in a black outline, thicker along the bottom and right: an 8-bit button's shadow.
            var face = PixelFace(fill);
            b.Background = Theme.Brush(face);
            hover = Theme.Brush(Blend(face, Theme.Rgb(1, 1, 1), 0.08));
            press = Theme.Brush(Blend(face, Theme.Rgb(0, 0, 0), 0.15));
            edge = Theme.Brush(Theme.Black);
            b.BorderBrush = edge;
            b.BorderThickness = new Thickness(2, 2, 3, 3);
            b.CornerRadius = new CornerRadius(0);
        }
        b.Resources["ButtonBackgroundPointerOver"] = hover;
        b.Resources["ButtonBackgroundPressed"] = press;
        b.Resources["ButtonBorderBrushPointerOver"] = edge;
        b.Resources["ButtonBorderBrushPressed"] = edge;
        b.Resources["ButtonForegroundPointerOver"] = Theme.Brush(Theme.Ink);
        b.Resources["ButtonForegroundPressed"] = Theme.Brush(Theme.Ink);
        b.Click += (_, _) => onClick();
        if (tip is not null) ToolTipService.SetToolTip(b, tip);
        return b;
    }

    public static Button PillButton(string text, Color color, Action onClick, string? glyph = null) =>
        Plain(H(5, glyph is null ? null : Icon(glyph, 8.5, color), Text(text, 9.5, color, FontWeights.SemiBold)), onClick,
              Theme.WithAlpha(color, 0.14), 7, new Thickness(S(10), S(4), S(10), S(4)));

    public static Button IconButton(string glyph, Action onClick, double size = 11, Color? color = null, string? tip = null, double box = 26) =>
        Plain(new Grid { Width = S(box), Height = S(box), Children = { Center(Icon(glyph, size, color ?? Theme.Dim)) } }, onClick,
              radius: box / 2, tip: tip);

    public static T Center<T>(T el) where T : FrameworkElement
    {
        el.HorizontalAlignment = HorizontalAlignment.Center;
        el.VerticalAlignment = VerticalAlignment.Center;
        return el;
    }

    // The Mac app's segmented control: a tray with a raised thumb under the chosen option.
    public static Border Segmented(string[] options, int selected, Action<int> onChange)
    {
        var row = H(2);
        for (var i = 0; i < options.Length; i++)
        {
            var index = i;
            var on = i == selected;
            var label = Text(options[i], 9.5, on ? Theme.Ink : Theme.Dim, on ? FontWeights.SemiBold : FontWeights.Medium);
            label.HorizontalAlignment = HorizontalAlignment.Center;
            row.Children.Add(Plain(label, () => onChange(index), on ? Theme.Thumb : Colors.Transparent, 6,
                                   new Thickness(S(9), S(3.5), S(9), S(3.5))));
        }
        return new Border
        {
            Child = row,
            Padding = new Thickness(S(2)),
            CornerRadius = new CornerRadius(Theme.Pixel ? 0 : S(8)),
            Background = Theme.Pixel ? Theme.Brush(Theme.PixelWell) : Theme.Keycap ? KeyWell() : Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.06)),
            BorderBrush = Theme.Pixel ? Theme.Brush(Theme.PixelEdge) : Theme.Keycap ? KeyWellEdge() : null,
            BorderThickness = new Thickness(Theme.Pixel ? 2 : Theme.Keycap ? 1 : 0),
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
        };
    }

    // The Mac's switch: a small accent pill with a white knob. WinUI's ToggleSwitch keeps room for a label, which
    // pushed it past the edge of narrow cards.
    public static FrameworkElement Switch(bool on, Action<bool> changed)
    {
        var knob = new Border
        {
            Width = S(13), Height = S(13), CornerRadius = new CornerRadius(Theme.Pixel ? 0 : S(6.5)),
            Background = Theme.Keycap ? Vertical(Theme.Rgb(1, 1, 1), Theme.Rgb(0.84, 0.84, 0.86)) : Theme.Brush(Theme.Rgb(1, 1, 1)),
            BorderBrush = Theme.Keycap ? Theme.Brush(Theme.Rgb(0, 0, 0, 0.35)) : null,
            BorderThickness = new Thickness(0, 0, 0, Theme.Keycap ? 1.5 : 0),
            HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left,
            Margin = new Thickness(S(2)),
            Transitions = [new RepositionThemeTransition()],
        };
        var track = new Grid
        {
            Width = S(30), Height = S(17), CornerRadius = new CornerRadius(Theme.Pixel ? 0 : S(8.5)),
            Background = Track(on),
            BorderBrush = Theme.Pixel ? Theme.Brush(Theme.Black) : Theme.Keycap ? KeyWellEdge() : null,
            BorderThickness = new Thickness(Theme.Pixel ? 2 : Theme.Keycap ? 1 : 0),
            Children = { knob },
        };
        var state = on;
        var button = Plain(track, () =>
        {
            state = !state;
            knob.HorizontalAlignment = state ? HorizontalAlignment.Right : HorizontalAlignment.Left;
            track.Background = Track(state);
            changed(state);
        }, radius: 8.5);
        button.HorizontalAlignment = HorizontalAlignment.Right;
        return button;
    }

    private static Brush Track(bool on) => (on, Theme.Keycap) switch
    {
        (true, true) => Vertical(Blend(Theme.Accent, Theme.Rgb(0, 0, 0), 0.25), Theme.Accent),
        (true, false) => Theme.Brush(Theme.Accent),
        (false, true) => KeyWell(),
        (false, false) when Theme.Pixel => Theme.Brush(Theme.PixelWell),
        _ => Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.18)),
    };

    // A settings or quick-settings row: icon, title over caption, and a control on the right.
    public static Grid Row(string? glyph, string title, string caption, UIElement? trailing)
    {
        var texts = V(1, Text(title, 11, weight: FontWeights.Medium), caption.Length == 0 ? null : Text(caption, 9, Theme.Faint));
        texts.VerticalAlignment = VerticalAlignment.Center;
        return Columns(10, (glyph is null ? null : Icon(glyph, 11, Theme.Dim), null), (texts, 1), (trailing, null));
    }

    // A horizontal level: filled share of a track, done with star columns so it needs no measured width.
    public static Grid Bar(double value, Color color, double height = 4)
    {
        value = Math.Clamp(double.IsFinite(value) ? value : 0, 0, 1);
        var g = new Grid
        {
            Height = S(height),
            CornerRadius = new CornerRadius(S(height / 2)),
            Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.08)),
        };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(value, 0.0001), GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Math.Max(1 - value, 0.0001), GridUnitType.Star) });
        var fill = new Border { Background = Theme.Brush(color), CornerRadius = new CornerRadius(S(height / 2)) };
        g.Children.Add(fill);
        return g;
    }

    // A labelled stat: coloured dot and label, big value, small caption.
    public static StackPanel Stat(string label, string value, string caption, Color dot) =>
        V(2,
          H(5, new Border { Width = S(5), Height = S(5), CornerRadius = new CornerRadius(S(2.5)), Background = Theme.Brush(dot) },
            Text(label, 9.5, Theme.Dim, FontWeights.Medium)),
          Text(value, 17, weight: FontWeights.Bold, display: true),
          Text(caption, 8.5, Theme.Faint));

    public static ScrollViewer Scroll(UIElement content) => new()
    {
        Content = content,
        VerticalScrollBarVisibility = ScrollBarVisibility.Hidden,
        HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
    };

    // An element can only have one parent; take it out of the old one before placing it again.
    public static T Detach<T>(T el) where T : FrameworkElement
    {
        switch (el.Parent)
        {
            case Panel panel: panel.Children.Remove(el); break;
            case Border border: border.Child = null; break;
            case ContentControl content: content.Content = null; break;
        }
        return el;
    }

    // Pages slide up a touch as they arrive, instead of popping in.
    public static TransitionCollection Arrive() => [new EntranceThemeTransition { FromVerticalOffset = S(10), FromHorizontalOffset = 0 }];

    // A short fade and drop, for the panel as it opens and the notch as it closes.
    public static void FadeIn(UIElement el, float drop = 6)
    {
        ElementCompositionPreview.SetIsTranslationEnabled(el, true);
        var visual = ElementCompositionPreview.GetElementVisual(el);
        var c = visual.Compositor;
        var ease = c.CreateCubicBezierEasingFunction(new System.Numerics.Vector2(0.2f, 0.8f), new System.Numerics.Vector2(0.2f, 1f));
        var fade = c.CreateScalarKeyFrameAnimation();
        fade.InsertKeyFrame(0, 0);
        fade.InsertKeyFrame(1, 1, ease);
        fade.Duration = TimeSpan.FromMilliseconds(220);
        var move = c.CreateVector3KeyFrameAnimation();
        move.InsertKeyFrame(0, new System.Numerics.Vector3(0, -drop, 0));
        move.InsertKeyFrame(1, System.Numerics.Vector3.Zero, ease);
        move.Duration = TimeSpan.FromMilliseconds(260);
        visual.StartAnimation("Opacity", fade);
        visual.StartAnimation("Translation", move);
    }

    public static Border Divider() => new() { Height = 1, Background = Theme.Brush(Theme.Stroke) };

    public static Color Blend(Color a, Color b, double t)
    {
        // Over a transparent face, the tint is just the second colour at that strength.
        if (a.A == 0) return Theme.WithAlpha(b, t);
        return Color.FromArgb(a.A, (byte)(a.R + (b.R - a.R) * t), (byte)(a.G + (b.G - a.G) * t), (byte)(a.B + (b.B - a.B) * t));
    }

    public static readonly Color Transparent = Colors.Transparent;

    // The UI thread's queue, set by the window, for work that finishes on a background thread.
    public static DispatcherQueue? Queue { get; set; }

    public static void Dispatch(Action action) => Queue?.TryEnqueue(() => action());
}

static class Colors
{
    public static readonly Color Transparent = Color.FromArgb(0, 0, 0, 0);
}
