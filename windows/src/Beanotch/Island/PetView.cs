using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using Windows.Foundation;
using Windows.UI;
using static Beanotch.Ui.Ui;

namespace Beanotch.Island;

public enum PetKind { Bean, Cat, Frog, Ghost }

// The pet that lives in the island's right corner, drawn pixel by pixel as on the Mac and redrawn eight times a
// second while it shows: it naps, sweats, eats, dances, jumps at alerts by the model's mood, and its eyes follow the
// pointer.
public sealed partial class PetView
{
    private sealed record Look(string[] Shape, Color Body, Color Shade, Color Socket, Color Pupil, Point[] Eyes, Point Mouth);

    private static Look Of(PetKind kind) => kind switch
    {
        PetKind.Cat => new([".#........#.", ".##......##.", ".####--####.", "############", "############",
                            "############", "############", ".##########.", "..########..", "..##....##.."],
                           Ui.Theme.Rgb(0.96, 0.6, 0.26), Ui.Theme.Rgb(0.74, 0.38, 0.14), White, Dark, [new(2.5, 3.5), new(7.5, 3.5)], new(6, 6.3)),
        PetKind.Frog => new([".###....###.", "#####..#####", "############", "############", "############",
                             "############", ".##########.", ".##########.", "..##....##..", "............"],
                            Ui.Theme.Rgb(0.42, 0.76, 0.36), Ui.Theme.Rgb(0.2, 0.48, 0.2), White, Dark, [new(1.5, 0.5), new(8.5, 0.5)], new(6, 4.8)),
        PetKind.Ghost => new(["...######...", "..########..", ".##########.", ".##########.", ".##########.",
                              ".##########.", ".##########.", ".##########.", ".###.##.###.", ".#...#...#.."],
                             Ui.Theme.Rgb(0.92, 0.92, 1), Ui.Theme.Rgb(0.32, 0.3, 0.45), Ui.Theme.Rgb(0.16, 0.15, 0.26), White,
                             [new(2.5, 3), new(7.5, 3)], new(6, 6.5)),
        _ => new(["....####....", "..########..", ".##########.", ".##########.", "############",
                  "############", "############", ".#######-##.", "..#####-##..", "....##-#...."],
                 Ui.Theme.Rgb(0.62, 0.4, 0.26), Ui.Theme.Rgb(0.36, 0.22, 0.14), White, Dark, [new(2.5, 3), new(7.5, 3)], new(6, 6.5)),
    };

    private static readonly Color White = Ui.Theme.Rgb(1, 1, 1), Dark = Ui.Theme.Rgb(0.12, 0.08, 0.06);
    private static readonly Color Blush = Ui.Theme.Rgb(1, 0.5, 0.55, 0.6), Water = Ui.Theme.Rgb(0.4, 0.75, 1);
    private const double Pixel = 1.9;

    private readonly Canvas canvas = new() { Width = S(18 * Pixel), Height = S(14 * Pixel), IsHitTestVisible = false };
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
    private double walked;
    private int frame;
    // Recent turns of the pointer near the island, to tell a shake.
    private readonly List<DateTimeOffset> turns = [];
    private int lastX, heading;

    public FrameworkElement View => canvas;
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
        canvas.RenderTransform = shift;
        if (anchor is not null)
        {
            // Takes the pointer, so it can be clicked, rested on and scrolled.
            canvas.IsHitTestVisible = true;
            canvas.Background = Ui.Theme.Brush(Ui.Theme.Rgb(0, 0, 0, 0));
        }
        if (still) { Draw(); return; }
        timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(125);
        timer.Tick += (_, _) => { frame++; Step(); Draw(); };
    }

    // Each frame: a step of its stroll, and a look for a shaking pointer (six quick turns within a second).
    private void Step()
    {
        var target = walkTo?.Invoke() ?? 0;
        walked = target > walked ? Math.Min(target, walked + 1 / 44.0) : Math.Max(target, walked - 1 / 44.0);
        shift.X = -walked * (walkDistance?.Invoke() ?? 0);
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
        canvas.Visibility = on ? Visibility.Visible : Visibility.Collapsed;
        if (timer is null) return;
        if (on && !timer.IsRunning) { Draw(); timer.Start(); }
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

    private void Draw()
    {
        canvas.Children.Clear();
        var m = mood();
        var pet = Of(kind());
        var look = Gaze();
        double dx = 0, dy = m switch
        {
            Model.PetMood.Dancing => frame % 4 < 2 ? 1 : 3,
            Model.PetMood.Surprised => frame % 6 < 3 ? 0.5 : 1.5,
            Model.PetMood.Sleepy or Model.PetMood.Tired => frame % 32 < 16 ? 2 : 2.5,
            Model.PetMood.Love or Model.PetMood.Party or Model.PetMood.Charged => frame % 8 < 4 ? 0.8 : 2,
            Model.PetMood.Walking => frame % 4 < 2 ? 1.6 : 2.2,
            _ => frame % 24 < 12 ? 2 : 2.3,
        };
        if (m == Model.PetMood.Panic) dx = frame % 2 == 0 ? -0.5 : 0.5;
        if (m == Model.PetMood.Sway) dx = Math.Sin(frame * 0.9) * 1.2;
        if (m == Model.PetMood.Dizzy) dx = Math.Sin(frame * 0.5) * 0.6;
        void Dot(double x, double y, Color color, double w = 1, double h = 1)
        {
            // A pixel larger than the grid, so no seams show between them at any scaling.
            var r = new Rectangle { Width = S(w * Pixel) + 0.8, Height = S(h * Pixel) + 0.8, Fill = Ui.Theme.Brush(color) };
            Canvas.SetLeft(r, S((x + 3 + dx) * Pixel));
            Canvas.SetTop(r, S((y + dy) * Pixel));
            canvas.Children.Add(r);
        }
        for (var y = 0; y < pet.Shape.Length; y++)
            for (var x = 0; x < pet.Shape[y].Length; x++)
                if (pet.Shape[y][x] != '.') Dot(x, y, pet.Shape[y][x] == '-' ? pet.Shade : pet.Body);
        if (pet.Socket != pet.Pupil && kind() != PetKind.Ghost) Dot(kind() == PetKind.Frog ? 4 : 2, 2, Ui.Theme.Rgb(1, 1, 1, 0.35));

        // Eyes: open ones look toward the pointer; a panicked one can't keep still.
        void Eyes(double height = 2, bool pupils = true, double jitter = 0)
        {
            foreach (var e in pet.Eyes)
            {
                Dot(e.X, e.Y + (2 - height), pet.Socket, 2, height);
                if (pupils)
                    Dot(e.X + 0.5 + look.X * 0.5 + jitter, e.Y + (2 - height) + Math.Max(0, height - 1) / 2 + look.Y * Math.Min(0.5, (height - 1) / 2), pet.Pupil);
            }
        }
        void Closed() { foreach (var e in pet.Eyes) Dot(e.X, e.Y + 1.3, pet.Socket, 2, 0.5); }
        var mouth = pet.Mouth;
        void Heart(double x, double y)
        {
            var pink = Ui.Theme.Rgb(1, 0.35, 0.45);
            Dot(x, y, pink); Dot(x + 2, y, pink); Dot(x, y + 1, pink, 3); Dot(x + 1, y + 2, pink);
        }
        var red = Ui.Theme.Red;
        switch (m)
        {
            case Model.PetMood.Love:
                foreach (var e in pet.Eyes) Dot(e.X, e.Y + 1, pet.Socket, 2, 0.6);
                if (kind() != PetKind.Frog) { Dot(pet.Eyes[0].X - 1, pet.Eyes[0].Y + 2.5, Blush, 1.5); Dot(pet.Eyes[1].X + 1.5, pet.Eyes[1].Y + 2.5, Blush, 1.5); }
                Dot(mouth.X - 1, mouth.Y, pet.Shade, 2, 0.6);
                Heart(12, 3 - frame % 12 / 4.0);
                break;
            case Model.PetMood.Dizzy:
                foreach (var e in pet.Eyes)
                {
                    Dot(e.X, e.Y, pet.Socket, 2, 2);
                    Dot(e.X + 0.5 + Math.Cos(frame * 0.8) * 0.5, e.Y + 0.5 + Math.Sin(frame * 0.8) * 0.5, pet.Pupil);
                }
                Dot(mouth.X - 1, mouth.Y, pet.Shade, 2, 0.6);
                Dot(5.5 + Math.Cos(frame * 0.4) * 5, -1 + Math.Sin(frame * 0.4) * 0.8, Ui.Theme.Rgb(1, 0.85, 0.3));
                break;
            case Model.PetMood.Sad:
                Eyes(1);
                Dot(mouth.X - 1, mouth.Y + 0.6, pet.Shade, 2, 0.5);
                Dot(mouth.X - 1.4, mouth.Y, pet.Shade, 0.6, 0.6); Dot(mouth.X + 0.8, mouth.Y, pet.Shade, 0.6, 0.6);
                Dot(pet.Eyes[0].X + 0.5, pet.Eyes[0].Y + 2 + frame % 12 / 3.0, Water, 0.8, 1.2);
                break;
            case Model.PetMood.Party:
                foreach (var e in pet.Eyes) { Dot(e.X, e.Y + 0.5, pet.Socket, 2, 0.6); Dot(e.X + 0.5, e.Y, pet.Socket, 1, 0.6); }
                Dot(mouth.X - 1.25, mouth.Y - 0.3, pet.Shade, 2.5, 1.4);
                Color[] confetti = [Ui.Theme.Rgb(1, 0.45, 0.7), Ui.Theme.Rgb(1, 0.85, 0.3), Ui.Theme.Rgb(0.3, 0.85, 1), Ui.Theme.Rgb(0.4, 0.9, 0.5), Ui.Theme.Rgb(1, 0.6, 0.25)];
                for (var i = 0; i < 5; i++) Dot((i * 37 + frame) % 16 - 2, (i * 13 + frame * 2) % 14 - 2, confetti[i], 0.8, 0.8);
                break;
            case Model.PetMood.Focus:
                Eyes(1.5);
                Dot(mouth.X - 0.5, mouth.Y, pet.Shade, 1, 0.6);
                break;
            case Model.PetMood.Coffee:
                Eyes(1);
                Dot(mouth.X - 1, mouth.Y, pet.Shade, 2, 0.6);
                Dot(11.8, 6, White, 2, 2); Dot(13.8, 6.5, White, 0.6, 1);
                Dot(12.3 + (frame % 8 < 4 ? 0 : 0.5), 4.5 - frame % 8 / 8.0, Ui.Theme.Rgb(1, 1, 1, 0.5), 0.6, 1);
                break;
            case Model.PetMood.Tired:
                Eyes(0.8);
                Dot(mouth.X - 0.75, mouth.Y, pet.Shade, 1.5, 0.5);
                Dot(11.8, 3, red, 2.6, 0.4); Dot(11.8, 4.6, red, 2.6, 0.4); Dot(11.8, 3, red, 0.4, 2); Dot(14, 3, red, 0.4, 2);
                Dot(14.4, 3.6, red, 0.4, 0.8); Dot(12.2, 3.4, red, 0.6, 1.2);
                break;
            case Model.PetMood.Charged:
                Eyes();
                Dot(mouth.X - 1, mouth.Y, pet.Shade, 2, 0.8);
                if (frame % 4 < 3)
                {
                    var bolt = Ui.Theme.Rgb(1, 0.85, 0.2);
                    Dot(14, 0.5, bolt, 1, 2); Dot(13, 2.5, bolt, 2, 0.8); Dot(13, 3.3, bolt, 1, 2);
                }
                break;
            case Model.PetMood.Hungry:
                Eyes();
                Dot(mouth.X - 0.75, mouth.Y - 0.2, pet.Shade, 1.5, 1.2);
                var bowl = Ui.Theme.Rgb(0.85, 0.85, 0.85);
                Dot(11.5, 8, bowl, 3, 0.6); Dot(12, 8.6, bowl, 2, 0.6);
                if (frame % 16 < 8) { Dot(13, 3, White, 1.2, 0.5); Dot(13.8, 3.3, White, 0.5, 1); Dot(13.3, 4.2, White, 0.5, 0.6); Dot(13.3, 5.2, White, 0.5, 0.5); }
                break;
            case Model.PetMood.Thirsty:
                Eyes(1.5);
                Dot(mouth.X - 0.75, mouth.Y, Ui.Theme.Rgb(1, 0.45, 0.5), 1.5, 1);
                Dot(12.5, 2 + frame % 8 / 4.0, Water, 1, 1.5);
                break;
            case Model.PetMood.Sleepy:
                Closed();
                Dot(14.5, 3 - frame % 24 / 8.0, Ui.Theme.Rgb(1, 1, 1, 0.8), 1.5, 0.5);
                break;
            case Model.PetMood.Panic:
                Eyes(jitter: frame % 2 == 0 ? -0.2 : 0.2);
                Dot(mouth.X - 1, mouth.Y + 0.5, pet.Shade, 2);
                Dot(12, 1 + frame % 6 / 3.0, Water, 1, 1.5);
                break;
            case Model.PetMood.Eating:
                Eyes(1.5);
                Dot(mouth.X - 1.25, mouth.Y, pet.Shade, 2.5, frame % 4 < 2 ? 1.5 : 0.5);
                if (frame % 4 < 2) Dot(-1, 7, Ui.Theme.Rgb(1, 1, 1, 0.7), 0.7, 0.7);
                break;
            case Model.PetMood.Surprised:
                Eyes();
                Dot(mouth.X - 0.75, mouth.Y, pet.Shade, 1.5, 1.5);
                Dot(13, 0.5, White, 1, 2.5); Dot(13, 3.5, White);
                break;
            case Model.PetMood.Late:
                Eyes(1);
                Dot(mouth.X - 1, mouth.Y - 0.2, pet.Shade, 2, frame % 32 < 12 ? 1.8 : 0.6);
                break;
            default:
                if (kind() != PetKind.Frog) { Dot(pet.Eyes[0].X - 1, pet.Eyes[0].Y + 2.5, Blush, 1.5); Dot(pet.Eyes[1].X + 1.5, pet.Eyes[1].Y + 2.5, Blush, 1.5); }
                if (frame % 40 == 0) Closed(); else Eyes();
                if (kind() == PetKind.Cat) Dot(mouth.X - 0.5, mouth.Y - 1, pet.Shade);
                var wide = kind() == PetKind.Frog;
                Dot(mouth.X - (wide ? 2 : 1), mouth.Y, pet.Shade, wide ? 4 : 2, 0.6);
                if (m == Model.PetMood.Dancing) Dot(14.5, 6 - frame % 16 / 4.0, Ui.Theme.Rgb(1, 1, 1, 0.85), 1, 2);
                break;
        }

        // What it has on: the cap for prayer or the focus headband first, else the chosen accessory.
        var top = kind() == PetKind.Cat ? 2 : 0;
        if (praying())
        {
            var cap = Ui.Theme.Rgb(0.12, 0.12, 0.12);
            Dot(3, top - 1.5, cap, 6, 1); Dot(2.5, top - 0.5, cap, 7, 0.8); Dot(2.5, top - 0.5, Ui.Theme.Rgb(0.3, 0.3, 0.3), 7, 0.3);
            return;
        }
        if (m == Model.PetMood.Focus)
        {
            Dot(0.5, 1.5, red, 11, 0.8); Dot(11.3, 1.8, red, 1.2, 0.6); Dot(12, 2.4, red, 0.8, 0.6);
            return;
        }
        switch (accessory())
        {
            case Services.PetAccessory.Scarf:
                var scarf = Ui.Theme.Rgb(0.9, 0.25, 0.3);
                Dot(1.5, 7.2, scarf, 9, 1); Dot(8.5, 8.2, scarf, 1.2, 1.4);
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
            case Services.PetAccessory.Cap:
                var accent = Ui.Theme.Accent;
                Dot(3, top - 1.6, accent, 6, 1.2); Dot(2, top - 0.5, accent, 8, 0.8); Dot(9.5, top - 0.2, accent, 2.5, 0.5);
                break;
            case Services.PetAccessory.Crown:
                var gold = Ui.Theme.Rgb(1, 0.8, 0.25);
                Dot(3, top - 0.9, gold, 6, 1); Dot(3, top - 2, gold, 1, 1.2); Dot(5.5, top - 2.2, gold, 1, 1.4); Dot(8, top - 2, gold, 1, 1.2);
                break;
        }
    }
}
