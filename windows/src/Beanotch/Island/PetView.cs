using System.Runtime.InteropServices;
using Microsoft.UI.Dispatching;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
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
    // Where the pet is on screen, in pixels, and how many pixels a point is; null looks straight ahead.
    private readonly Func<(Point At, double Scale)?>? anchor;
    private int frame;

    public FrameworkElement View => canvas;

    public PetView(Func<Model.PetMood> mood, Func<PetKind> kind, Func<(Point At, double Scale)?>? anchor = null, bool still = false)
    {
        this.mood = mood;
        this.kind = kind;
        this.anchor = anchor;
        if (still) { Draw(); return; }
        timer = DispatcherQueue.GetForCurrentThread().CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(125);
        timer.Tick += (_, _) => { frame++; Draw(); };
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
            Model.PetMood.Sleepy => frame % 32 < 16 ? 2 : 2.5,
            _ => frame % 24 < 12 ? 2 : 2.3,
        };
        if (m == Model.PetMood.Panic) dx = frame % 2 == 0 ? -0.5 : 0.5;
        void Dot(double x, double y, Color color, double w = 1, double h = 1)
        {
            var r = new Rectangle { Width = S(w * Pixel) + 0.3, Height = S(h * Pixel) + 0.3, Fill = Ui.Theme.Brush(color) };
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
        switch (m)
        {
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
    }
}
