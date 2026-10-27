using Microsoft.UI.Dispatching;
using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using Windows.UI.Text;

namespace Beanotch.Ui;

// Small builders in the spirit of the Mac app's SwiftUI views: the whole UI is written in C#, which keeps it
// buildable (and checkable) without the XAML compiler.
public static class Ui
{
    // Mac points to Windows pixels: the same nominal size reads smaller on Windows.
    public const double K = 1.3;
    public static double S(double v) => Math.Round(v * K, 1);

    private static readonly FontFamily SystemText = new("Segoe UI Variable Text, Segoe UI");
    private static readonly FontFamily SystemDisplay = new("Segoe UI Variable Display, Segoe UI");
    private static readonly Dictionary<string, FontFamily> Faces = [];

    public static AppFont AppFont { get; set; } = AppFont.System;

    // A bundled font is one file per weight. Regular and Bold carry the plain family name; Medium and SemiBold carry
    // their weight in it ("Inter SemiBold"), which is how Windows tells them apart.
    public static FontFamily FontFor(FontWeight weight, bool display = false)
    {
        if (Theme.Retro is not null) return Pixel;
        var (file, family) = AppFont switch
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
    // VT323 is a terminal font with a small body, so it's set a size up to read like the others (as on the Mac).
    private static readonly FontFamily Pixel = new("ms-appx:///Assets/Fonts/VT323-Regular.ttf#VT323");
    private const double PixelScale = 1.32;
    public static readonly FontFamily Icons = new("Segoe Fluent Icons, Segoe MDL2 Assets");

    public static TextBlock Text(string text, double size, Color? color = null, FontWeight? weight = null, bool mono = false,
                                 bool wrap = false, bool display = false)
    {
        var t = new TextBlock
        {
            Text = text,
            FontSize = S(Theme.Retro is null ? size : size * PixelScale),
            FontFamily = mono && Theme.Retro is null ? Mono : FontFor(weight ?? FontWeights.Normal, display),
            FontWeight = weight ?? FontWeights.Normal,
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
        CornerRadius = new CornerRadius(S(radius)),
        Background = Theme.Brush(Theme.Surface),
        BorderBrush = Theme.Brush(Theme.Stroke),
        BorderThickness = new Thickness(1),
    };

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
        var hover = Theme.Brush(Blend(fill, Theme.Ink, 0.08));
        var press = Theme.Brush(Blend(fill, Theme.Ink, 0.14));
        b.Resources["ButtonBackgroundPointerOver"] = hover;
        b.Resources["ButtonBackgroundPressed"] = press;
        b.Resources["ButtonBorderBrushPointerOver"] = Theme.Brush(Colors.Transparent);
        b.Resources["ButtonBorderBrushPressed"] = Theme.Brush(Colors.Transparent);
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
            CornerRadius = new CornerRadius(S(8)),
            Background = Theme.Brush(Theme.WithAlpha(Theme.Ink, 0.06)),
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
            Width = S(13), Height = S(13), CornerRadius = new CornerRadius(S(6.5)),
            Background = Theme.Brush(Theme.Rgb(1, 1, 1)),
            HorizontalAlignment = on ? HorizontalAlignment.Right : HorizontalAlignment.Left,
            Margin = new Thickness(S(2)),
        };
        var track = new Grid
        {
            Width = S(30), Height = S(17), CornerRadius = new CornerRadius(S(8.5)),
            Background = Theme.Brush(on ? Theme.Accent : Theme.WithAlpha(Theme.Ink, 0.18)),
            Children = { knob },
        };
        var state = on;
        var button = Plain(track, () =>
        {
            state = !state;
            knob.HorizontalAlignment = state ? HorizontalAlignment.Right : HorizontalAlignment.Left;
            track.Background = Theme.Brush(state ? Theme.Accent : Theme.WithAlpha(Theme.Ink, 0.18));
            changed(state);
        }, radius: 8.5);
        button.HorizontalAlignment = HorizontalAlignment.Right;
        return button;
    }

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
