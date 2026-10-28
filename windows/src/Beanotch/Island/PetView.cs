using System.Runtime.InteropServices;
using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Foundation;
using Windows.UI;
using static Beanotch.Ui.Ui;

namespace Beanotch.Island;

public enum PetKind { Bean, Cat, Frog, Ghost, Dog, Panda, Bunny, Robot }

// The pet that lives in the island's left corner, drawn as on the Mac: a 12 × 10 grid for its eyes and mouth, its
// body at twice that detail from a few simple shapes, lit from the top left. It's painted into one small bitmap thirty
// times a second while it shows (cheaper than hundreds of rectangles), and its eyes follow the pointer.
public sealed partial class PetView
{
    private enum Cell : byte { None, Body, Shade, Light, Accent, Dark }

    private sealed record Look(Color Body, Color Shade, Color Light, Color Accent, Color Dark, Color Socket, Color Pupil, Color Ink,
                               Point[] Eyes, Point Mouth, Point? Nose);

    private static readonly Color White = Ui.Theme.Rgb(1, 1, 1), Brown = Ui.Theme.Rgb(0.12, 0.08, 0.06);
    private static readonly Color Blush = Ui.Theme.Rgb(1, 0.5, 0.55, 0.55), Water = Ui.Theme.Rgb(0.4, 0.75, 1);

    private static Color Mix(Color a, Color b, double t) => Color.FromArgb(a.A, (byte)(a.R + (b.R - a.R) * t), (byte)(a.G + (b.G - a.G) * t), (byte)(a.B + (b.B - a.B) * t));

    private static Look Of(PetKind kind)
    {
        Color R(double r, double g, double b) => Ui.Theme.Rgb(r, g, b);
        var (body, shade) = kind switch
        {
            PetKind.Cat => (R(0.96, 0.6, 0.26), R(0.74, 0.38, 0.14)),
            PetKind.Frog => (R(0.42, 0.76, 0.36), R(0.2, 0.48, 0.2)),
            PetKind.Ghost => (R(0.92, 0.92, 1), R(0.62, 0.6, 0.78)),
            PetKind.Dog => (R(0.86, 0.68, 0.46), R(0.62, 0.44, 0.26)),
            PetKind.Panda => (R(0.96, 0.96, 0.95), R(0.72, 0.72, 0.74)),
            PetKind.Bunny => (R(0.95, 0.9, 0.92), R(0.74, 0.66, 0.72)),
            PetKind.Robot => (R(0.66, 0.72, 0.8), R(0.4, 0.45, 0.54)),
            _ => (R(0.62, 0.4, 0.26), R(0.36, 0.22, 0.14)),
        };
        var light = kind switch { PetKind.Frog => R(0.7, 0.9, 0.56), PetKind.Ghost or PetKind.Panda or PetKind.Bunny => White, _ => Mix(body, White, 0.32) };
        var accent = kind switch { PetKind.Cat or PetKind.Bunny => R(1, 0.62, 0.68), PetKind.Dog => R(0.96, 0.86, 0.72), PetKind.Robot => R(1, 0.36, 0.38), _ => shade };
        var dark = kind switch { PetKind.Dog => R(0.45, 0.3, 0.18), PetKind.Panda => R(0.14, 0.14, 0.16), PetKind.Robot => R(0.12, 0.15, 0.2), _ => shade };
        var socket = kind switch { PetKind.Ghost => R(0.16, 0.15, 0.26), PetKind.Robot => R(0.36, 0.92, 1), _ => White };
        var pupil = kind switch { PetKind.Ghost => White, PetKind.Robot => R(0.08, 0.5, 0.62), _ => Brown };
        var ink = kind switch { PetKind.Robot => socket, PetKind.Panda or PetKind.Bunny or PetKind.Ghost => R(0.3, 0.26, 0.32), _ => shade };
        Point[] eyes = kind switch
        {
            PetKind.Frog => [new(1.6, 0.8), new(8.4, 0.8)],
            PetKind.Cat => [new(2.5, 3.8), new(7.5, 3.8)],
            PetKind.Bunny => [new(2.8, 4.2), new(7.2, 4.2)],
            PetKind.Robot => [new(3.2, 3.8), new(6.8, 3.8)],
            PetKind.Panda => [new(2.6, 3.4), new(7.4, 3.4)],
            _ => [new(2.5, 3), new(7.5, 3)],
        };
        var mouth = kind switch
        {
            PetKind.Frog => new Point(6, 5), PetKind.Cat => new Point(6, 6.6), PetKind.Dog => new Point(6, 7.3),
            PetKind.Bunny => new Point(6, 7.1), PetKind.Panda => new Point(6, 7), _ => new Point(6, 6.5),
        };
        Point? nose = kind switch { PetKind.Dog or PetKind.Panda => new Point(6, 6.1), PetKind.Cat or PetKind.Bunny => new Point(6, 6), _ => null };
        return new(body, shade, light, accent, dark, socket, pupil, ink, eyes, mouth, nose);
    }

    private static bool Ellipse(double x, double y, double cx, double cy, double rx, double ry) =>
        Math.Pow((x - cx) / rx, 2) + Math.Pow((y - cy) / ry, 2) <= 1;

    private static bool Inside(PetKind kind, double x, double y)
    {
        switch (kind)
        {
            case PetKind.Cat:
                bool Ear(double tip) => y >= 0 && y <= 3 && Math.Abs(x - tip) <= y / 3 * 1.9;
                return Ellipse(x, y, 6, 6.2, 6, 4.2) || Ear(1.6) || Ear(10.4);
            case PetKind.Frog: return Ellipse(x, y, 6, 5.8, 6, 4.2) || Ellipse(x, y, 2.6, 1.8, 1.9, 1.7) || Ellipse(x, y, 9.4, 1.8, 1.9, 1.7);
            case PetKind.Ghost: return Ellipse(x, y, 6, 5, 5.1, 5) && y <= 5 || x >= 0.9 && x <= 11.1 && y > 5 && y <= 9 + 0.7 * Math.Sin(x * Math.PI / 1.5);
            case PetKind.Dog: return Ellipse(x, y, 6, 5.6, 5.4, 4.5) || Ellipse(x, y, 1, 4, 1.3, 2.8) || Ellipse(x, y, 11, 4, 1.3, 2.8);
            case PetKind.Panda: return Ellipse(x, y, 6, 5.6, 5.8, 4.6) || Ellipse(x, y, 1.8, 1.6, 1.5, 1.4) || Ellipse(x, y, 10.2, 1.6, 1.5, 1.4);
            case PetKind.Bunny: return Ellipse(x, y, 6, 6.2, 5.4, 4) || Ellipse(x, y, 3.6, 0.4, 0.95, 2.6) || Ellipse(x, y, 8.4, 0.4, 0.95, 2.6);
            case PetKind.Robot:
                var box = x >= 1 && x <= 11 && y >= 1.4 && y <= 9.6;
                var corner = new[] { (2.2, 2.6), (9.8, 2.6), (2.2, 8.4), (9.8, 8.4) }.Any(c =>
                    (x < 2.2 || x > 9.8) && (y < 2.6 || y > 8.4) && Math.Sqrt(Math.Pow(x - c.Item1, 2) + Math.Pow(y - c.Item2, 2)) > 1.2
                    && Math.Abs(x - c.Item1) < 1.3 && Math.Abs(y - c.Item2) < 1.3);
                return box && !corner || Math.Abs(x - 6) < 0.3 && y > -0.6 && y < 1.4 || Ellipse(x, y, 6, -0.9, 0.7, 0.7);
            default: return Ellipse(x, y, 6, 5, 6, 5);
        }
    }

    private static Cell Detail(PetKind kind, double x, double y) => kind switch
    {
        PetKind.Bean => Math.Abs(x - (8.4 - (y - 6.2) * 0.75)) < 0.45 && y > 5.8 ? Cell.Shade : Cell.None,
        PetKind.Cat => y >= 1 && y <= 2.9 && (Math.Abs(x - 1.6) <= (y - 1) / 2 * 0.9 || Math.Abs(x - 10.4) <= (y - 1) / 2 * 0.9) ? Cell.Accent : Cell.None,
        PetKind.Dog => Ellipse(x, y, 1, 4, 1.3, 2.8) || Ellipse(x, y, 11, 4, 1.3, 2.8) ? Cell.Dark : Ellipse(x, y, 6, 6.8, 2.2, 1.5) ? Cell.Accent : Cell.None,
        PetKind.Panda => Ellipse(x, y, 1.8, 1.6, 1.5, 1.4) || Ellipse(x, y, 10.2, 1.6, 1.5, 1.4) || Ellipse(x, y, 3.5, 4.3, 1.7, 1.5) || Ellipse(x, y, 8.5, 4.3, 1.7, 1.5) ? Cell.Dark : Cell.None,
        PetKind.Bunny => Ellipse(x, y, 3.6, 0.6, 0.45, 2) || Ellipse(x, y, 8.4, 0.6, 0.45, 2) ? Cell.Accent : Cell.None,
        PetKind.Robot => Ellipse(x, y, 6, -0.9, 0.7, 0.7) ? Cell.Accent : x >= 2.2 && x <= 9.8 && y >= 2.8 && y <= 7.8 ? Cell.Dark : Cell.None,
        PetKind.Frog => Ellipse(x, y, 6, 7.2, 3.8, 1.8) ? Cell.Light : Cell.None,
        _ => Cell.None,
    };

    // The body at half a grid square, rows from y −2 to 10, worked out once per kind.
    private static readonly Dictionary<PetKind, Cell[,]> Bodies = [];

    private static Cell[,] BodyOf(PetKind kind)
    {
        if (Bodies.TryGetValue(kind, out var known)) return known;
        var cells = new Cell[24, 24];
        for (var row = 0; row < 24; row++)
            for (var col = 0; col < 24; col++)
            {
                double x = (col + 0.5) / 2, y = (row + 0.5) / 2 - 2;
                if (!Inside(kind, x, y)) continue;
                var d = Detail(kind, x, y);
                cells[row, col] = d != Cell.None ? d
                    : !Inside(kind, x + 0.8, y + 0.8) || !Inside(kind, x, y + 0.9) ? Cell.Shade
                    : !Inside(kind, x - 0.7, y - 0.7) ? Cell.Light : Cell.Body;
            }
        return Bodies[kind] = cells;
    }

    private const double Pixel = 1.9;
    // Bitmap pixels per grid square: drawn large and shown smaller, so it stays sharp at any scaling.
    private const int Res = 8;
    private const int Width = 18 * Res, Height = 14 * Res;

    private readonly Image image = new() { Width = S(18 * Pixel), Height = S(14 * Pixel), Stretch = Stretch.Fill, IsHitTestVisible = false };
    private readonly Grid host = new();
    private readonly WriteableBitmap bitmap = new(Width, Height);
    private readonly byte[] pixels = new byte[Width * Height * 4];
    private readonly DispatcherQueueTimer? timer;
    private readonly Func<Model.PetMood> mood;
    private readonly Func<PetKind> kind;
    private readonly Func<Services.PetAccessory> accessory;
    private readonly Func<bool> praying;
    // Where the pet is on screen, in pixels, and how many pixels a point is; null looks straight ahead.
    private readonly Func<(Point At, double Scale)?>? anchor;
    // Where it's walking to (0 home, 1 the far end) and how far that is, in pixels of the island.
    private readonly Func<double>? walkTo, walkDistance;
    private readonly TranslateTransform shift = new();
    private readonly ScaleTransform turn = new();
    private double walked;
    private readonly DateTime born = DateTime.UtcNow;
    // Recent turns of the pointer near the island, to tell a shake.
    private readonly List<DateTimeOffset> turns = [];
    private int lastX, heading;

    public FrameworkElement View => host;
    public event Action? Shaken;

    public PetView(Func<Model.PetMood> mood, Func<PetKind> kind, Func<(Point At, double Scale)?>? anchor = null, bool still = false,
                   Func<Services.PetAccessory>? accessory = null, Func<bool>? praying = null, Func<double>? walkTo = null,
                   Func<double>? walkDistance = null)
    {
        this.mood = mood;
        this.kind = kind;
        this.anchor = anchor;
        this.accessory = accessory ?? (() => Services.PetAccessory.None);
        this.praying = praying ?? (() => false);
        this.walkTo = walkTo;
        this.walkDistance = walkDistance;
        image.Source = bitmap;
        image.RenderTransformOrigin = new Point(0.5, 0.5);
        image.RenderTransform = turn;
        host.Children.Add(image);
        host.RenderTransform = shift;
        if (anchor is not null)
        {
            // Takes the pointer, so it can be clicked, rested on and scrolled.
            host.IsHitTestVisible = true;
            host.Background = Ui.Theme.Brush(Ui.Theme.Rgb(0, 0, 0, 0));
        }
        if (still) { Draw(0); return; }
        timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(33);
        timer.Tick += (_, _) => { Step(); Draw((DateTime.UtcNow - born).TotalSeconds); };
    }

    // Each frame: a step of its stroll, and a look for a shaking pointer (six quick turns within a second).
    private void Step()
    {
        var target = walkTo?.Invoke() ?? 0;
        walked = target > walked ? Math.Min(target, walked + 1 / 170.0) : Math.Max(target, walked - 1 / 170.0);
        shift.X = walked * (walkDistance?.Invoke() ?? 0);
        if (anchor?.Invoke() is not { } a || !GetCursorPos(out var c)) return;
        if (Math.Abs(c.X - a.At.X) > 500 * a.Scale || Math.Abs(c.Y - a.At.Y) > 200 * a.Scale) return;
        var dx = c.X - lastX;
        lastX = c.X;
        if (Math.Abs(dx) < 5 * a.Scale) return;
        if (heading != 0 && Math.Sign(dx) != Math.Sign(heading))
        {
            var now = DateTimeOffset.Now;
            turns.RemoveAll(t => now - t > TimeSpan.FromSeconds(1));
            turns.Add(now);
            if (turns.Count >= 6) { turns.Clear(); Shaken?.Invoke(); }
        }
        heading = dx;
    }

    public void Show(bool on)
    {
        host.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        if (timer is null) return;
        if (on && !timer.IsRunning) { Draw((DateTime.UtcNow - born).TotalSeconds); timer.Start(); }
        if (!on) timer.Stop();
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct CursorPoint { public int X, Y; }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetCursorPos(out CursorPoint point);

    // Where the pointer is from the pet, as -1…1 across and down.
    private Point Gaze()
    {
        if (anchor?.Invoke() is not { } a || !GetCursorPos(out var c)) return new(0, 0);
        return new(Math.Clamp((c.X - a.At.X) / (160 * a.Scale), -1, 1), Math.Clamp((c.Y - a.At.Y) / (120 * a.Scale), -1, 1));
    }

    // A steady pseudo-random number in 0…1 for a whole number, so idle habits differ from one stretch to the next.
    private static double Chance(long n)
    {
        var x = unchecked((ulong)n * 0x9E3779B97F4A7C15);
        x ^= x >> 29; x = unchecked(x * 0xBF58476D1CE4E5B9); x ^= x >> 32;
        return x % 10_000 / 10_000.0;
    }

    private double dx, dy;

    // A rectangle on the 12 × 10 grid, blended into the bitmap.
    private void Dot(double x, double y, Color color, double w = 1, double h = 1)
    {
        int x0 = (int)Math.Round((x + 3 + dx) * Res), y0 = (int)Math.Round((y + dy) * Res);
        int x1 = (int)Math.Round((x + 3 + dx + w) * Res), y1 = (int)Math.Round((y + dy + h) * Res);
        double a = color.A / 255.0;
        for (var py = Math.Max(0, y0); py < Math.Min(Height, y1); py++)
            for (var px = Math.Max(0, x0); px < Math.Min(Width, x1); px++)
            {
                var i = (py * Width + px) * 4;
                // Premultiplied BGRA, painted over what's there.
                pixels[i] = (byte)(color.B * a + pixels[i] * (1 - a));
                pixels[i + 1] = (byte)(color.G * a + pixels[i + 1] * (1 - a));
                pixels[i + 2] = (byte)(color.R * a + pixels[i + 2] * (1 - a));
                pixels[i + 3] = (byte)(255 * a + pixels[i + 3] * (1 - a));
            }
    }

    private void Draw(double t)
    {
        Array.Clear(pixels);
        var m = mood();
        var k = kind();
        var pet = Of(k);
        var frame = (int)(t * 8);
        var look = Gaze();
        // Idle habits, a couple of seconds out of every ten while it's content: a look around, a yawn, a wiggle, a twitch.
        var stretch = (long)(t / 10);
        var into = t % 10;
        var habit = m == Model.PetMood.Happy && into < 2.4 ? (int)(Chance(stretch) * 5) : -1;
        if (habit == 0) look = new(Math.Sin(into / 2.4 * Math.PI * 2) * 0.9, 0);
        var yawning = habit == 1 && into > 0.3 && into < 2;

        dx = 0; dy = 2;
        switch (m)
        {
            case Model.PetMood.Dancing or Model.PetMood.Groove:
                dy = 2 - Math.Abs(Math.Sin(t * Math.PI * 2.4)) * 1.2;
                if (m == Model.PetMood.Groove) dx = Math.Sin(t * Math.PI * 2.4) * 0.6;
                break;
            case Model.PetMood.Surprised: dy = 2 - Math.Abs(Math.Sin(t * Math.PI * 3)) * 1.2; break;
            case Model.PetMood.Panic: dx = Math.Sin(t * 60) * 0.5; break;
            case Model.PetMood.Sleepy or Model.PetMood.Tired: dy = 2 + Math.Sin(t * 1.4) * 0.3; break;
            case Model.PetMood.Love or Model.PetMood.Party or Model.PetMood.Charged or Model.PetMood.Wave: dy = 2 - Math.Abs(Math.Sin(t * Math.PI * 2)) * 1.1; break;
            case Model.PetMood.Walking: dy = 2 - Math.Abs(Math.Sin(t * Math.PI * 4)) * 0.5; break;
            case Model.PetMood.Sway: dx = Math.Sin(t * 7) * 1.2; break;
            case Model.PetMood.Dizzy: dx = Math.Sin(t * 4) * 0.6; break;
            case Model.PetMood.Ball: dy = 2 - Math.Abs(Math.Sin(t * Math.PI * 1.6)) * 0.6; break;
            default: dy = 2 + Math.Sin(t * 1.8) * 0.18; break;
        }
        if (habit == 2) dx = Math.Sin(into * 9) * 0.5;
        dx = Math.Round(dx * 2) / 2;
        dy = Math.Round(dy * 4) / 4;
        // A twirl: narrowing to an edge and widening again, flipped half way.
        var spin = m == Model.PetMood.Spin ? Math.Cos(t % 0.9 / 0.9 * Math.PI * 2) : 1;
        turn.ScaleX = Math.Max(0.08, Math.Abs(spin)) * (spin < 0 ? -1 : 1);

        var twitch = habit == 3 && (int)(into * 6) % 2 == 0 ? -0.5 : 0;
        var body = BodyOf(k);
        for (var row = 0; row < 24; row++)
            for (var col = 0; col < 24; col++)
            {
                var cell = body[row, col];
                if (cell == Cell.None) continue;
                double x = col / 2.0, y = row / 2.0 - 2;
                var ear = k is PetKind.Cat or PetKind.Bunny ? y < 2.6 : k == PetKind.Dog && (x < 2.3 || x > 9.7);
                var color = cell switch { Cell.Shade => pet.Shade, Cell.Light => pet.Light, Cell.Accent => pet.Accent, Cell.Dark => pet.Dark, _ => pet.Body };
                Dot(x, y + (ear ? twitch : 0), color, 0.5, 0.5);
            }
        if (k is not (PetKind.Ghost or PetKind.Robot)) Dot(k == PetKind.Frog ? 4.2 : 2.2, k == PetKind.Bunny ? 2.8 : 1.8, Ui.Theme.Rgb(1, 1, 1, 0.45), 1, 0.5);
        if (pet.Nose is { } nose) Dot(nose.X - 0.5, nose.Y, k is PetKind.Panda or PetKind.Dog ? pet.Dark : pet.Accent, 1, 0.6);

        var mouth = pet.Mouth;
        var cycle = 3.6 + Chance((long)(t / 3.6)) * 2.4;
        var phase = t % cycle;
        var blinking = phase < 0.12 || Chance((long)(t / 3.6) + 7) > 0.7 && phase > 0.28 && phase < 0.4;
        void Closed() { foreach (var e in pet.Eyes) Dot(e.X, e.Y + 1.3, k == PetKind.Robot ? pet.Socket : pet.Ink, 2, 0.5); }
        void Eyes(double height = 2, bool pupils = true, double jitter = 0)
        {
            if (blinking || yawning) { Closed(); return; }
            foreach (var e in pet.Eyes)
            {
                Dot(e.X, e.Y + (2 - height), pet.Socket, 2, height);
                if (!pupils) continue;
                double px = e.X + 0.5 + look.X * 0.5 + jitter, py = e.Y + (2 - height) + Math.Max(0, height - 1) / 2 + look.Y * Math.Min(0.5, (height - 1) / 2);
                Dot(px, py, pet.Pupil);
                if (height >= 2 && k is not (PetKind.Robot or PetKind.Panda)) Dot(px + 0.5, py, Ui.Theme.Rgb(1, 1, 1, 0.85), 0.5, 0.5);
            }
        }
        void Cheeks()
        {
            if (k is PetKind.Frog or PetKind.Robot) return;
            Dot(pet.Eyes[0].X - 1, pet.Eyes[0].Y + 2.5, Blush, 1.5); Dot(pet.Eyes[1].X + 1.5, pet.Eyes[1].Y + 2.5, Blush, 1.5);
        }
        void Smile(bool wide = false) => Dot(mouth.X - (wide ? 2 : 1), mouth.Y, pet.Ink, wide ? 4 : 2, 0.6);
        void Heart(double x, double y)
        {
            var pink = Ui.Theme.Rgb(1, 0.35, 0.45);
            Dot(x, y, pink); Dot(x + 2, y, pink); Dot(x, y + 1, pink, 3); Dot(x + 1, y + 2, pink);
        }
        void Note(double x, double y)
        {
            var c = Ui.Theme.Rgb(1, 1, 1, 0.85);
            Dot(x + 0.6, y, c, 0.4, 2); Dot(x, y + 1.6, c, 0.8, 0.6); Dot(x + 0.6, y, c, 1, 0.4);
        }
        var red = Ui.Theme.Red;
        switch (m)
        {
            case Model.PetMood.Sleepy:
                Closed();
                var rise = t % 3;
                Dot(14.5 + rise * 0.3, 3 - rise, Ui.Theme.Rgb(1, 1, 1, 0.8 - rise * 0.2), 1.5, 0.5);
                break;
            case Model.PetMood.Panic:
                Eyes(jitter: Math.Sin(t * 40) * 0.2);
                Dot(mouth.X - 1, mouth.Y + 0.5, pet.Ink, 2);
                Dot(12, 1 + t % 0.75 * 2.6, Water, 1, 1.5);
                break;
            case Model.PetMood.Eating:
                Eyes(1.5);
                Dot(mouth.X - 1.25, mouth.Y, pet.Ink, 2.5, 0.5 + Math.Abs(Math.Sin(t * 8)));
                if (frame % 4 < 2) Dot(-1, 7, Ui.Theme.Rgb(1, 1, 1, 0.7), 0.7, 0.7);
                break;
            case Model.PetMood.Surprised:
                Eyes();
                Dot(mouth.X - 0.75, mouth.Y, pet.Ink, 1.5, 1.5);
                Dot(13, 0.5, White, 1, 2.5); Dot(13, 3.5, White);
                break;
            case Model.PetMood.Late:
                Eyes(1);
                Dot(mouth.X - 1, mouth.Y - 0.2, pet.Ink, 2, 0.6 + Math.Max(0, Math.Sin(t * 1.2)) * 1.2);
                break;
            case Model.PetMood.Thirsty:
                Eyes(1.5);
                Dot(mouth.X - 0.75, mouth.Y, Ui.Theme.Rgb(1, 0.45, 0.5), 1.5, 1);
                Dot(12.5, 2 + t % 1 * 2, Water, 1, 1.5);
                break;
            case Model.PetMood.Love:
                foreach (var e in pet.Eyes) Dot(e.X, e.Y + 1, pet.Socket, 2, 0.6);
                Cheeks();
                Smile();
                Heart(12, 3 - t % 1.5 * 2);
                break;
            case Model.PetMood.Dizzy:
                foreach (var e in pet.Eyes)
                {
                    Dot(e.X, e.Y, pet.Socket, 2, 2);
                    Dot(e.X + 0.5 + Math.Cos(t * 6.4) * 0.5, e.Y + 0.5 + Math.Sin(t * 6.4) * 0.5, pet.Pupil);
                }
                Smile();
                Dot(5.5 + Math.Cos(t * 3.2) * 5, -1 + Math.Sin(t * 3.2) * 0.8, Ui.Theme.Rgb(1, 0.85, 0.3));
                break;
            case Model.PetMood.Sad:
                Eyes(1);
                Dot(mouth.X - 1, mouth.Y + 0.6, pet.Ink, 2, 0.5);
                Dot(mouth.X - 1.4, mouth.Y, pet.Ink, 0.6, 0.6); Dot(mouth.X + 0.8, mouth.Y, pet.Ink, 0.6, 0.6);
                Dot(pet.Eyes[0].X + 0.5, pet.Eyes[0].Y + 2 + t % 1.5 * 2, Water, 0.8, 1.2);
                break;
            case Model.PetMood.Party or Model.PetMood.Groove:
                foreach (var e in pet.Eyes) { Dot(e.X, e.Y + 0.5, pet.Socket, 2, 0.6); Dot(e.X + 0.5, e.Y, pet.Socket, 1, 0.6); }
                Dot(mouth.X - 1.25, mouth.Y - 0.3, pet.Ink, 2.5, 1.4);
                if (m == Model.PetMood.Party)
                {
                    Color[] confetti = [Ui.Theme.Rgb(1, 0.45, 0.7), Ui.Theme.Rgb(1, 0.85, 0.3), Ui.Theme.Rgb(0.3, 0.85, 1), Ui.Theme.Rgb(0.4, 0.9, 0.5), Ui.Theme.Rgb(1, 0.6, 0.25)];
                    for (var i = 0; i < 5; i++) Dot((i * 37 + frame) % 16 - 2, (i * 13 + frame * 2) % 14 - 2, confetti[i], 0.8, 0.8);
                }
                else
                {
                    var up = t % 1.1 * 3;
                    Note(14.2, 5 - up);
                    Note(-1.6, 4.5 - up * 0.8);
                }
                break;
            case Model.PetMood.Focus:
                Eyes(1.5);
                Dot(mouth.X - 0.5, mouth.Y, pet.Ink, 1, 0.6);
                break;
            case Model.PetMood.Coffee:
                Eyes(1);
                Smile();
                Dot(11.8, 6, White, 2, 2); Dot(13.8, 6.5, White, 0.6, 1);
                var steam = t % 1.2 / 1.2;
                Dot(12.3 + Math.Sin(t * 4) * 0.3, 4.6 - steam * 1.6, Ui.Theme.Rgb(1, 1, 1, 0.55 - steam * 0.4), 0.6, 1);
                break;
            case Model.PetMood.Tired:
                Eyes(0.8);
                Dot(mouth.X - 0.75, mouth.Y, pet.Ink, 1.5, 0.5);
                Dot(11.8, 3, red, 2.6, 0.4); Dot(11.8, 4.6, red, 2.6, 0.4); Dot(11.8, 3, red, 0.4, 2); Dot(14, 3, red, 0.4, 2);
                Dot(14.4, 3.6, red, 0.4, 0.8); Dot(12.2, 3.4, red, 0.6, 1.2);
                break;
            case Model.PetMood.Charged:
                Eyes();
                Dot(mouth.X - 1, mouth.Y, pet.Ink, 2, 0.8);
                if (frame % 4 < 3)
                {
                    var bolt = Ui.Theme.Rgb(1, 0.85, 0.2);
                    Dot(14, 0.5, bolt, 1, 2); Dot(13, 2.5, bolt, 2, 0.8); Dot(13, 3.3, bolt, 1, 2);
                }
                break;
            case Model.PetMood.Hungry:
                Eyes();
                Dot(mouth.X - 0.75, mouth.Y - 0.2, pet.Ink, 1.5, 1.2);
                var bowl = Ui.Theme.Rgb(0.85, 0.85, 0.85);
                Dot(11.5, 8, bowl, 3, 0.6); Dot(12, 8.6, bowl, 2, 0.6);
                if (frame % 16 < 8) { Dot(13, 3, White, 1.2, 0.5); Dot(13.8, 3.3, White, 0.5, 1); Dot(13.3, 4.2, White, 0.5, 0.6); Dot(13.3, 5.2, White, 0.5, 0.5); }
                break;
            case Model.PetMood.Wave:
                Cheeks();
                Eyes();
                Smile(true);
                var paw = Math.Sin(t * Math.PI * 4) * 0.8;
                Dot(12 + paw, 3, pet.Body, 1.4, 1.4); Dot(12.4 + paw, 4.4, pet.Body, 0.8, 1.6);
                break;
            case Model.PetMood.Ball:
                var hop = Math.Abs(Math.Sin(t * Math.PI * 1.6));
                double bx = 13.2 + Math.Sin(t * 1.1) * 0.8, by = 8.2 - hop * 4;
                look = new(0.9, by < 6 ? -0.6 : 0.4);
                Cheeks();
                if (blinking) Closed();
                else foreach (var e in pet.Eyes) { Dot(e.X, e.Y, pet.Socket, 2, 2); Dot(e.X + 0.5 + look.X * 0.5, e.Y + 0.5 + look.Y * 0.5, pet.Pupil); }
                Smile();
                Dot(bx, by, Ui.Theme.Accent, 1.6, 1.6); Dot(bx + 0.3, by + 0.2, Ui.Theme.Rgb(1, 1, 1, 0.6), 0.5, 0.5);
                break;
            case Model.PetMood.Spin:
                Eyes();
                Smile();
                break;
            default:
                Cheeks();
                Eyes();
                if (k == PetKind.Cat) Dot(mouth.X - 0.5, mouth.Y - 1, pet.Ink, 1, 0.5);
                if (yawning) Dot(mouth.X - 0.8, mouth.Y - 0.6, Ui.Theme.Rgb(0.12, 0.12, 0.12), 1.6, 0.6 + Math.Sin((into - 0.3) / 1.7 * Math.PI) * 1.6);
                else Smile(k == PetKind.Frog);
                if (m == Model.PetMood.Dancing) Note(14.5, 6 - t % 2 / 2 * 4);
                break;
        }
        Wear(k, m, pet);
        using (var stream = bitmap.PixelBuffer.AsStream()) stream.Write(pixels, 0, pixels.Length);
        bitmap.Invalidate();
    }

    // What it has on: the cap for prayer or the focus headband first, else the chosen accessory.
    private void Wear(PetKind k, Model.PetMood m, Look pet)
    {
        var top = k switch { PetKind.Cat => 2, PetKind.Bunny => 2.2, PetKind.Robot => 1.4, _ => 0 };
        if (praying())
        {
            var cap = Ui.Theme.Rgb(0.12, 0.12, 0.12);
            Dot(3, top - 1.5, cap, 6, 1); Dot(2.5, top - 0.5, cap, 7, 0.8); Dot(2.5, top - 0.5, Ui.Theme.Rgb(0.3, 0.3, 0.3), 7, 0.3);
            return;
        }
        if (m == Model.PetMood.Focus)
        {
            var band = Ui.Theme.Red;
            Dot(0.5, 1.5, band, 11, 0.8); Dot(11.3, 1.8, band, 1.2, 0.6); Dot(12, 2.4, band, 0.8, 0.6);
            return;
        }
        switch (accessory())
        {
            case Services.PetAccessory.Scarf:
                var scarf = Ui.Theme.Rgb(0.9, 0.25, 0.3);
                Dot(1.5, 7.6, scarf, 9, 1); Dot(1.5, 7.6, Mix(scarf, White, 0.25), 9, 0.3); Dot(8.5, 8.6, scarf, 1.2, 1.4);
                break;
            case Services.PetAccessory.Glasses:
                var rim = Ui.Theme.Rgb(0.05, 0.05, 0.05);
                foreach (var e in pet.Eyes)
                {
                    Dot(e.X - 0.4, e.Y - 0.4, rim, 2.8, 0.4); Dot(e.X - 0.4, e.Y + 2, rim, 2.8, 0.4);
                    Dot(e.X - 0.4, e.Y - 0.4, rim, 0.4, 2.8); Dot(e.X + 2, e.Y - 0.4, rim, 0.4, 2.8);
                }
                Dot(pet.Eyes[0].X + 2.4, pet.Eyes[0].Y + 0.4, rim, pet.Eyes[1].X - pet.Eyes[0].X - 2.4, 0.4);
                break;
            case Services.PetAccessory.Sunglasses:
                var lens = Ui.Theme.Rgb(0.06, 0.06, 0.06);
                foreach (var e in pet.Eyes) { Dot(e.X - 0.4, e.Y, lens, 2.8, 1.8); Dot(e.X, e.Y + 0.3, Ui.Theme.Rgb(1, 1, 1, 0.35), 0.8, 0.4); }
                Dot(pet.Eyes[0].X + 2.4, pet.Eyes[0].Y + 0.3, lens, pet.Eyes[1].X - pet.Eyes[0].X - 2.4, 0.5);
                break;
            case Services.PetAccessory.Cap:
                var accent = Ui.Theme.Accent;
                Dot(3, top - 1.6, accent, 6, 1.2); Dot(2, top - 0.5, accent, 8, 0.8); Dot(9.5, top - 0.2, accent, 2.5, 0.5);
                break;
            case Services.PetAccessory.Crown:
                var gold = Ui.Theme.Rgb(1, 0.8, 0.25);
                Dot(3, top - 0.9, gold, 6, 1); Dot(3, top - 2, gold, 1, 1.2); Dot(5.5, top - 2.2, gold, 1, 1.4); Dot(8, top - 2, gold, 1, 1.2);
                Dot(5.7, top - 0.7, Ui.Theme.Rgb(0.9, 0.2, 0.3), 0.6, 0.6);
                break;
            case Services.PetAccessory.Headphones:
                var arc = Ui.Theme.Rgb(0.16, 0.16, 0.16);
                Dot(1, top - 1.2, arc, 10, 0.6); Dot(0.6, top - 0.8, arc, 0.6, 3.5); Dot(10.8, top - 0.8, arc, 0.6, 3.5);
                Dot(-0.2, top + 2.2, Ui.Theme.Accent, 1.4, 2.4); Dot(10.8, top + 2.2, Ui.Theme.Accent, 1.4, 2.4);
                break;
            case Services.PetAccessory.Bow:
                var pink = Ui.Theme.Rgb(1, 0.42, 0.62);
                Dot(7.6, top - 0.8, pink, 1.5, 1.4); Dot(10, top - 0.8, pink, 1.5, 1.4); Dot(9.1, top - 0.5, Mix(pink, Ui.Theme.Rgb(0, 0, 0), 0.2), 0.9, 0.9);
                break;
            case Services.PetAccessory.Santa:
                var santa = Ui.Theme.Rgb(0.88, 0.18, 0.22);
                Dot(3, top - 1.6, santa, 6, 1.4); Dot(4.5, top - 2.6, santa, 3.6, 1.2); Dot(7.6, top - 2.4, santa, 1.6, 0.8);
                Dot(2.4, top - 0.4, White, 7.2, 0.8); Dot(9, top - 2.6, White, 1.1, 1.1);
                break;
        }
    }
}
